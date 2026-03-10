#!/bin/bash

# MySQL 环境搭建脚本
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
MYSQL_ENABLED="${MYSQL_ENABLED:-true}"
MYSQL_VERSION="${MYSQL_VERSION:-8.0}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-mysql123456}"
MYSQL_DIR="${MYSQL_DIR:-/opt/mysql}"
MYSQL_NETWORK="${MYSQL_NETWORK:-traefik-public}"
MYSQL_MEMORY_LIMIT="${MYSQL_MEMORY_LIMIT:-512m}"

# 判断 MySQL 是否启用（支持多种 true 值）
# 兼容低版本 Bash（macOS 默认 Bash 3.2）
is_mysql_enabled() {
    # 转换为小写（兼容 Bash 3.2）
    local enabled_lower=$(echo "$MYSQL_ENABLED" | tr '[:upper:]' '[:lower:]')
    case "$enabled_lower" in
        true|on|1|y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 停止 MySQL 容器
stop_mysql() {
    echo -e "${YELLOW}=== 检查并停止 MySQL 容器 ===${NC}"
    
    if docker ps -a | grep -q "mysql"; then
        echo "发现 MySQL 容器，正在停止..."
        docker stop mysql 2>/dev/null || true
        docker rm mysql 2>/dev/null || true
        echo -e "${GREEN}✓ MySQL 容器已停止${NC}"
    else
        echo "未发现 MySQL 容器，无需操作"
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

    if ! docker network ls | grep -q "${MYSQL_NETWORK}"; then
        echo -e "${YELLOW}警告: 网络 ${MYSQL_NETWORK} 不存在，正在创建...${NC}"
        docker network create ${MYSQL_NETWORK}
        echo -e "${GREEN}✓ 网络 ${MYSQL_NETWORK} 创建成功${NC}"
    else
        echo "网络 ${MYSQL_NETWORK} 已存在"
    fi

    docker network ls | grep ${MYSQL_NETWORK}
}

# 创建 MySQL 配置
setup_mysql() {
    echo -e "${YELLOW}=== 步骤 2: 配置 MySQL ===${NC}"

    mkdir -p ${MYSQL_DIR}
    cd ${MYSQL_DIR}

    # 生成 docker-compose.yml - 使用 Docker Volume 管理数据
    # 注意：不设置 MYSQL_DATABASE，各产品需要自行创建所需的数据库
    cat > ${MYSQL_DIR}/docker-compose.yml << EOF
services:
  mysql:
    image: mysql:${MYSQL_VERSION}
    container_name: mysql
    restart: unless-stopped
    # 注意：不映射端口到宿主机，仅在 Docker 内部网络可访问
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_ROOT_HOST=%
    volumes:
      - mysql_data:/var/lib/mysql
    command: --default-authentication-plugin=mysql_native_password
    deploy:
      resources:
        limits:
          memory: ${MYSQL_MEMORY_LIMIT}
    networks:
      - ${MYSQL_NETWORK}

volumes:
  mysql_data:
    name: mysql_data

networks:
  ${MYSQL_NETWORK}:
    external: true
EOF

    echo -e "${GREEN}✓ MySQL 配置文件已生成${NC}"
    echo -e "${YELLOW}版本: ${MYSQL_VERSION}${NC}"
    echo -e "${YELLOW}网络: ${MYSQL_NETWORK} (仅内部访问)${NC}"
    echo -e "${YELLOW}数据存储: Docker Volume (mysql_data)${NC}"
}

# 启动 MySQL
start_mysql() {
    echo -e "${YELLOW}=== 步骤 3: 启动 MySQL ===${NC}"

    cd ${MYSQL_DIR}

    # 停止并删除旧容器（如果存在）
    if docker ps -a | grep -q "mysql"; then
        echo "停止旧容器..."
        docker compose down 2>/dev/null || true
        docker stop mysql 2>/dev/null || true
        docker rm mysql 2>/dev/null || true
    fi

    # 检查本地是否已有镜像，有则跳过拉取
    if docker images | grep -q "mysql.*${MYSQL_VERSION}"; then
        echo "镜像 mysql:${MYSQL_VERSION} 已存在，跳过拉取"
    else
        echo "正在拉取 MySQL 镜像..."
        docker pull mysql:${MYSQL_VERSION} || {
            echo -e "${YELLOW}尝试从国内镜像拉取...${NC}"
            docker pull m.daocloud.io/docker.io/library/mysql:${MYSQL_VERSION}
            docker tag m.daocloud.io/docker.io/library/mysql:${MYSQL_VERSION} mysql:${MYSQL_VERSION}
        }
    fi

    docker compose up -d

    echo "等待 MySQL 启动..."
    sleep 10

    # 检查容器状态
    if docker ps | grep -q "mysql"; then
        echo -e "${GREEN}✓ MySQL 启动成功${NC}"
        docker ps | grep mysql
        echo ""
        echo -e "${GREEN}连接信息 (内部网络访问):${NC}"
        echo "  服务名: mysql"
        echo "  端口: 3306"
        echo "  用户名: root"
        echo "  密码: ${MYSQL_ROOT_PASSWORD}"
        echo ""
        echo -e "${YELLOW}注意: 各产品需自行创建所需的数据库${NC}"
        echo ""
        echo -e "${GREEN}其他容器连接示例:${NC}"
        echo "  mysql://root:${MYSQL_ROOT_PASSWORD}@mysql:3306/your_database_name"
        echo ""
        echo -e "${YELLOW}注意: MySQL 仅在 Docker 网络内部可访问${NC}"
        echo -e "${YELLOW}外部访问请使用: docker exec -it mysql mysql -uroot -p${NC}"
    else
        echo -e "${RED}✗ MySQL 启动失败，请检查日志${NC}"
        docker logs mysql 2>&1 || true
        exit 1
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "  MySQL ${MYSQL_VERSION} 环境管理脚本"
    echo "========================================"
    echo ""

    check_root
    check_docker

    # 判断是否启用 MySQL
    if is_mysql_enabled; then
        echo -e "${GREEN}MySQL 开关: 启用${NC}"
        echo ""
        check_network
        setup_mysql
        start_mysql

        echo ""
        echo "========================================"
        echo -e "${GREEN}MySQL 环境搭建完成!${NC}"
        echo "========================================"
        echo ""
        echo "配置目录: ${MYSQL_DIR}/"
        echo "数据卷: mysql_data"
        echo ""
        echo "常用命令:"
        echo "  docker ps                           - 查看运行中的容器"
        echo "  docker logs mysql                   - 查看 MySQL 日志"
        echo "  docker exec -it mysql mysql -uroot -p  - 进入 MySQL shell"
        echo "  cd ${MYSQL_DIR} && docker compose logs -f  - 实时查看日志"
        echo "  docker volume ls | grep mysql       - 查看数据卷"
        echo "  docker volume inspect mysql_data    - 查看数据卷详情"
        echo ""
    else
        echo -e "${YELLOW}MySQL 开关: 禁用${NC}"
        echo ""
        stop_mysql

        echo ""
        echo "========================================"
        echo -e "${YELLOW}MySQL 已禁用，容器已停止（如果存在）${NC}"
        echo "========================================"
        echo ""
    fi
}

# 执行主函数
main
