#!/bin/bash

# PostgreSQL 环境搭建脚本
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
POSTGRES_ENABLED="${POSTGRES_ENABLED:-true}"
POSTGRES_VERSION="${POSTGRES_VERSION:-16}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres123456}"
POSTGRES_DIR="${POSTGRES_DIR:-/opt/postgres}"
POSTGRES_NETWORK="${TRAEFIK_NETWORK:-traefik-public}"
POSTGRES_MEMORY_LIMIT="${POSTGRES_MEMORY_LIMIT:-512m}"

# 判断 PostgreSQL 是否启用（支持多种 true 值）
# 兼容低版本 Bash（macOS 默认 Bash 3.2）
is_postgres_enabled() {
    # 转换为小写（兼容 Bash 3.2）
    local enabled_lower=$(echo "$POSTGRES_ENABLED" | tr '[:upper:]' '[:lower:]')
    case "$enabled_lower" in
        true|on|1|y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 停止 PostgreSQL 容器
stop_postgres() {
    echo -e "${YELLOW}=== 检查并停止 PostgreSQL 容器 ===${NC}"
    
    if docker ps -a | grep -q "postgres"; then
        echo "发现 PostgreSQL 容器，正在停止..."
        docker stop postgres 2>/dev/null || true
        docker rm postgres 2>/dev/null || true
        echo -e "${GREEN}✓ PostgreSQL 容器已停止${NC}"
    else
        echo "未发现 PostgreSQL 容器，无需操作"
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

    if ! docker network ls | grep -q "${POSTGRES_NETWORK}"; then
        echo -e "${YELLOW}警告: 网络 ${POSTGRES_NETWORK} 不存在，正在创建...${NC}"
        docker network create ${POSTGRES_NETWORK}
        echo -e "${GREEN}✓ 网络 ${POSTGRES_NETWORK} 创建成功${NC}"
    else
        echo "网络 ${POSTGRES_NETWORK} 已存在"
    fi

    docker network ls | grep ${POSTGRES_NETWORK}
}

# 创建 PostgreSQL 配置
setup_postgres() {
    echo -e "${YELLOW}=== 步骤 2: 配置 PostgreSQL ===${NC}"

    mkdir -p ${POSTGRES_DIR}
    cd ${POSTGRES_DIR}

    # 生成 docker-compose.yml - 使用 Docker Volume 管理数据
    # 注意：不设置 POSTGRES_DB，各产品需要自行创建所需的数据库
    cat > ${POSTGRES_DIR}/docker-compose.yml << EOF
services:
  postgres:
    image: postgres:${POSTGRES_VERSION}
    container_name: postgres
    restart: unless-stopped
    # 注意：不映射端口到宿主机，仅在 Docker 内部网络可访问
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          memory: ${POSTGRES_MEMORY_LIMIT}
    networks:
      - ${POSTGRES_NETWORK}

volumes:
  postgres_data:
    name: postgres_data

networks:
  ${POSTGRES_NETWORK}:
    external: true
EOF

    echo -e "${GREEN}✓ PostgreSQL 配置文件已生成${NC}"
    echo -e "${YELLOW}版本: ${POSTGRES_VERSION}${NC}"
    echo -e "${YELLOW}网络: ${POSTGRES_NETWORK} (仅内部访问)${NC}"
    echo -e "${YELLOW}数据存储: Docker Volume (postgres_data)${NC}"
}

# 启动 PostgreSQL
start_postgres() {
    echo -e "${YELLOW}=== 步骤 3: 启动 PostgreSQL ===${NC}"

    cd ${POSTGRES_DIR}

    # 停止并删除旧容器（如果存在）
    if docker ps -a | grep -q "postgres"; then
        echo "停止旧容器..."
        docker compose down 2>/dev/null || true
        docker stop postgres 2>/dev/null || true
        docker rm postgres 2>/dev/null || true
    fi

    # 检查本地是否已有镜像，有则跳过拉取
    if docker images | grep -q "postgres.*${POSTGRES_VERSION}"; then
        echo "镜像 postgres:${POSTGRES_VERSION} 已存在，跳过拉取"
    else
        echo "正在拉取 PostgreSQL 镜像..."
        docker pull postgres:${POSTGRES_VERSION} || {
            echo -e "${YELLOW}尝试从国内镜像拉取...${NC}"
            docker pull m.daocloud.io/docker.io/library/postgres:${POSTGRES_VERSION}
            docker tag m.daocloud.io/docker.io/library/postgres:${POSTGRES_VERSION} postgres:${POSTGRES_VERSION}
        }
    fi

    docker compose up -d

    echo "等待 PostgreSQL 启动..."
    sleep 5

    # 检查容器状态
    if docker ps | grep -q "postgres"; then
        echo -e "${GREEN}✓ PostgreSQL 启动成功${NC}"
        docker ps | grep postgres
        echo ""
        echo -e "${GREEN}连接信息 (内部网络访问):${NC}"
        echo "  服务名: postgres"
        echo "  端口: 5432"
        echo "  用户名: ${POSTGRES_USER}"
        echo "  密码: ${POSTGRES_PASSWORD}"
        echo ""
        echo -e "${YELLOW}注意: 各产品需自行创建所需的数据库${NC}"
        echo ""
        echo -e "${GREEN}其他容器连接示例:${NC}"
        echo "  postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/your_database_name"
        echo ""
        echo -e "${YELLOW}注意: PostgreSQL 仅在 Docker 网络内部可访问${NC}"
        echo -e "${YELLOW}外部访问请使用: docker exec -it postgres psql -U ${POSTGRES_USER}${NC}"
    else
        echo -e "${RED}✗ PostgreSQL 启动失败，请检查日志${NC}"
        docker logs postgres 2>&1 || true
        exit 1
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "  PostgreSQL ${POSTGRES_VERSION} 环境管理脚本"
    echo "========================================"
    echo ""

    check_root
    check_docker

    # 判断是否启用 PostgreSQL
    if is_postgres_enabled; then
        echo -e "${GREEN}PostgreSQL 开关: 启用${NC}"
        echo ""
        check_network
        setup_postgres
        start_postgres

        echo ""
        echo "========================================"
        echo -e "${GREEN}PostgreSQL 环境搭建完成!${NC}"
        echo "========================================"
        echo ""
        echo "配置目录: ${POSTGRES_DIR}/"
        echo "数据卷: postgres_data"
        echo ""
        echo "常用命令:"
        echo "  docker ps                           - 查看运行中的容器"
        echo "  docker logs postgres                - 查看 PostgreSQL 日志"
        echo "  docker exec -it postgres psql -U ${POSTGRES_USER}  - 进入 PostgreSQL shell"
        echo "  cd ${POSTGRES_DIR} && docker compose logs -f  - 实时查看日志"
        echo "  docker volume ls | grep postgres    - 查看数据卷"
        echo "  docker volume inspect postgres_data - 查看数据卷详情"
        echo ""
    else
        echo -e "${YELLOW}PostgreSQL 开关: 禁用${NC}"
        echo ""
        stop_postgres

        echo ""
        echo "========================================"
        echo -e "${YELLOW}PostgreSQL 已禁用，容器已停止（如果存在）${NC}"
        echo "========================================"
        echo ""
    fi
}

# 执行主函数
main
