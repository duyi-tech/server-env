#!/bin/bash

# MongoDB 6.0 环境搭建脚本
# 使用方法: sudo ./setup.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载项目根目录的 .env 文件
if [ -f "${PROJECT_ROOT}/.env" ]; then
    echo -e "${YELLOW}加载环境变量: ${PROJECT_ROOT}/.env${NC}"
    export $(cat "${PROJECT_ROOT}/.env" | grep -v '^#' | xargs)
else
    echo -e "${RED}错误: 项目根目录 .env 文件不存在${NC}"
    exit 1
fi

# 设置默认值（使用 .env 中的值或默认值）
MONGO_ENABLED="${MONGO_ENABLED:-true}"
MONGO_VERSION="${MONGO_VERSION:-6.0}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME:-root}"
MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD:-mongo123456}"
MONGO_DIR="${MONGO_DIR:-/opt/mongodb}"
MONGO_NETWORK="${TRAEFIK_NETWORK:-traefik-public}"
MONGO_MEMORY_LIMIT="${MONGO_MEMORY_LIMIT:-512m}"

# 判断 MongoDB 是否启用（支持多种 true 值）
# 兼容低版本 Bash（macOS 默认 Bash 3.2）
is_mongo_enabled() {
    # 转换为小写（兼容 Bash 3.2）
    local enabled_lower=$(echo "$MONGO_ENABLED" | tr '[:upper:]' '[:lower:]')
    case "$enabled_lower" in
        true|on|1|y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 停止 MongoDB 容器
stop_mongodb() {
    echo -e "${YELLOW}=== 检查并停止 MongoDB 容器 ===${NC}"
    
    if docker ps -a | grep -q "mongodb"; then
        echo "发现 MongoDB 容器，正在停止..."
        docker stop mongodb 2>/dev/null || true
        docker rm mongodb 2>/dev/null || true
        echo -e "${GREEN}✓ MongoDB 容器已停止${NC}"
    else
        echo "未发现 MongoDB 容器，无需操作"
    fi
}

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用 sudo 或以 root 用户运行此脚本${NC}"
        exit 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误: Docker 未安装，请先安装 Docker${NC}"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}错误: Docker Compose 未安装，请先安装 Docker Compose${NC}"
        exit 1
    fi
}

# 检查共享网络是否存在
check_network() {
    echo -e "${YELLOW}=== 步骤 1: 检查 Docker 网络 ===${NC}"

    if ! docker network ls | grep -q "${MONGO_NETWORK}"; then
        echo -e "${YELLOW}警告: 网络 ${MONGO_NETWORK} 不存在，正在创建...${NC}"
        docker network create ${MONGO_NETWORK}
        echo -e "${GREEN}✓ 网络 ${MONGO_NETWORK} 创建成功${NC}"
    else
        echo "网络 ${MONGO_NETWORK} 已存在"
    fi

    docker network ls | grep ${MONGO_NETWORK}
}

# 创建 MongoDB 配置
setup_mongodb() {
    echo -e "${YELLOW}=== 步骤 2: 配置 MongoDB ===${NC}"

    mkdir -p ${MONGO_DIR}
    cd ${MONGO_DIR}

    # 生成 docker-compose.yml - 使用 Docker Volume 管理数据
    cat > ${MONGO_DIR}/docker-compose.yml << EOF
services:
  mongodb:
    image: mongo:${MONGO_VERSION}
    container_name: mongodb
    restart: unless-stopped
    # 注意：不映射端口到宿主机，仅在 Docker 内部网络可访问
    environment:
      - MONGO_INITDB_ROOT_USERNAME=${MONGO_ROOT_USERNAME}
      - MONGO_INITDB_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD}
    volumes:
      - mongodb_data:/data/db
      - mongodb_config:/data/configdb
      - mongodb_backup:/backup
    command: mongod --auth --bind_ip_all
    deploy:
      resources:
        limits:
          memory: ${MONGO_MEMORY_LIMIT}
    networks:
      - ${MONGO_NETWORK}

volumes:
  mongodb_data:
    name: mongodb_data
  mongodb_config:
    name: mongodb_config
  mongodb_backup:
    name: mongodb_backup

networks:
  ${MONGO_NETWORK}:
    external: true
EOF

    echo -e "${GREEN}✓ MongoDB 配置文件已生成${NC}"
    echo -e "${YELLOW}版本: ${MONGO_VERSION}${NC}"
    echo -e "${YELLOW}网络: ${MONGO_NETWORK} (仅内部访问)${NC}"
    echo -e "${YELLOW}数据存储: Docker Volume (mongodb_data)${NC}"
}

# 启动 MongoDB
start_mongodb() {
    echo -e "${YELLOW}=== 步骤 3: 启动 MongoDB ===${NC}"

    cd ${MONGO_DIR}

    # 停止并删除旧容器（如果存在）
    if docker ps -a | grep -q "mongodb"; then
        echo "停止旧容器..."
        docker compose down 2>/dev/null || true
        docker stop mongodb 2>/dev/null || true
        docker rm mongodb 2>/dev/null || true
    fi

    # 检查本地是否已有镜像，有则跳过拉取
    if docker images | grep -q "mongo.*${MONGO_VERSION}"; then
        echo "镜像 mongo:${MONGO_VERSION} 已存在，跳过拉取"
    else
        echo "正在拉取 MongoDB 镜像..."
        docker pull mongo:${MONGO_VERSION} || {
            echo -e "${YELLOW}尝试从国内镜像拉取...${NC}"
            docker pull m.daocloud.io/docker.io/library/mongo:${MONGO_VERSION}
            docker tag m.daocloud.io/docker.io/library/mongo:${MONGO_VERSION} mongo:${MONGO_VERSION}
        }
    fi

    docker compose up -d

    echo "等待 MongoDB 启动..."
    sleep 5

    # 检查容器状态
    if docker ps | grep -q "mongodb"; then
        echo -e "${GREEN}✓ MongoDB 启动成功${NC}"
        docker ps | grep mongodb
        echo ""
        echo -e "${GREEN}连接信息 (内部网络访问):${NC}"
        echo "  服务名: mongodb"
        echo "  端口: 27017"
        echo "  用户名: ${MONGO_ROOT_USERNAME}"
        echo "  密码: ${MONGO_ROOT_PASSWORD}"
        echo ""
        echo -e "${GREEN}其他容器连接字符串:${NC}"
        echo "  mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@mongodb:27017/<database>?authSource=admin"
        echo ""
        echo -e "${YELLOW}注意: MongoDB 仅在 Docker 网络内部可访问${NC}"
        echo -e "${YELLOW}外部访问请使用: docker exec -it mongodb mongosh${NC}"
    else
        echo -e "${RED}✗ MongoDB 启动失败，请检查日志${NC}"
        docker logs mongodb 2>&1 || true
        exit 1
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "  MongoDB ${MONGO_VERSION} 环境管理脚本"
    echo "========================================"
    echo ""

    check_root
    check_docker

    # 判断是否启用 MongoDB
    if is_mongo_enabled; then
        echo -e "${GREEN}MongoDB 开关: 启用${NC}"
        echo ""
        check_network
        setup_mongodb
        start_mongodb

        echo ""
        echo "========================================"
        echo -e "${GREEN}MongoDB 环境搭建完成!${NC}"
        echo "========================================"
        echo ""
        echo "配置目录: ${MONGO_DIR}/"
        echo "数据卷: mongodb_data"
        echo "配置卷: mongodb_config"
        echo "备份卷: mongodb_backup"
        echo ""
        echo "常用命令:"
        echo "  docker ps                       - 查看运行中的容器"
        echo "  docker logs mongodb             - 查看 MongoDB 日志"
        echo "  docker exec -it mongodb mongosh - 进入 MongoDB shell"
        echo "  cd ${MONGO_DIR} && docker compose logs -f  - 实时查看日志"
        echo "  docker volume ls | grep mongo   - 查看数据卷"
        echo "  docker volume inspect mongodb_data - 查看数据卷详情"
        echo ""
    else
        echo -e "${YELLOW}MongoDB 开关: 禁用${NC}"
        echo ""
        stop_mongodb

        echo ""
        echo "========================================"
        echo -e "${YELLOW}MongoDB 已禁用，容器已停止（如果存在）${NC}"
        echo "========================================"
        echo ""
    fi
}

# 执行主函数
main
