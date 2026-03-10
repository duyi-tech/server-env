#!/bin/bash

# Traefik 共享反向代理环境搭建脚本
# 使用方法: sudo ./setup.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置变量
NETWORK_NAME="traefik-public"
TRAEFIK_DIR="${TRAEFIK_DIR:-/opt/traefik}"
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

# 设置默认值
TRAEFIK_EMAIL="${TRAEFIK_EMAIL:-your-email@example.com}"
TRAEFIK_NETWORK="${TRAEFIK_NETWORK:-traefik-public}"
TRAEFIK_LOG_LEVEL="${TRAEFIK_LOG_LEVEL:-INFO}"
TRAEFIK_HTTP_REDIRECT="${TRAEFIK_HTTP_REDIRECT:-false}"

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

# 创建共享网络
create_network() {
    echo -e "${YELLOW}=== 步骤 1: 创建 Docker 共享网络 ===${NC}"

    if docker network ls | grep -q "${NETWORK_NAME}"; then
        echo "网络 ${NETWORK_NAME} 已存在，跳过创建"
    else
        docker network create ${NETWORK_NAME}
        echo -e "${GREEN}✓ 网络 ${NETWORK_NAME} 创建成功${NC}"
    fi

    docker network ls | grep ${NETWORK_NAME}
}

# 创建 Traefik 目录和配置
setup_traefik() {
    echo -e "${YELLOW}=== 步骤 2: 配置 Traefik ===${NC}"

    mkdir -p ${TRAEFIK_DIR}/letsencrypt
    cd ${TRAEFIK_DIR}

    # 生成 traefik.yml
    if [[ "${TRAEFIK_HTTP_REDIRECT}" == "true" ]]; then
        # 启用 HTTP -> HTTPS 重定向
        cat > ${TRAEFIK_DIR}/traefik.yml << EOF
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: ${TRAEFIK_NETWORK}

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${TRAEFIK_EMAIL}
      storage: /letsencrypt/acme.json
      tlsChallenge: {}

log:
  level: ${TRAEFIK_LOG_LEVEL}
EOF
    else
        # 不启用重定向，HTTP 和 HTTPS 独立访问
        cat > ${TRAEFIK_DIR}/traefik.yml << EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: ${TRAEFIK_NETWORK}

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${TRAEFIK_EMAIL}
      storage: /letsencrypt/acme.json
      tlsChallenge: {}

log:
  level: ${TRAEFIK_LOG_LEVEL}
EOF
    fi

    # 生成 docker-compose.yml
    cat > ${TRAEFIK_DIR}/docker-compose.yml << EOF
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
    environment:
      - TRAEFIK_LOG_LEVEL=${TRAEFIK_LOG_LEVEL}
      - TRAEFIK_PROVIDERS_DOCKER_NETWORK=${TRAEFIK_NETWORK}
      - TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${TRAEFIK_EMAIL}
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/letsencrypt/acme.json
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_TLSCHALLENGE=true
      - TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80
      - TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443
      - TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_TO=websecure
      - TRAEFIK_ENTRYPOINTS_WEB_HTTP_REDIRECTIONS_ENTRYPOINT_SCHEME=https
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
EOF

    echo -e "${GREEN}✓ Traefik 配置文件已生成${NC}"
    echo -e "${YELLOW}使用邮箱: ${TRAEFIK_EMAIL}${NC}"

    # 设置权限
    touch ${TRAEFIK_DIR}/letsencrypt/acme.json
    chmod 600 ${TRAEFIK_DIR}/letsencrypt/acme.json
}

# 启动 Traefik
start_traefik() {
    echo -e "${YELLOW}=== 步骤 3: 启动 Traefik ===${NC}"

    cd ${TRAEFIK_DIR}

    # 停止并删除旧容器（如果存在）
    if docker ps -a | grep -q "traefik"; then
        echo "停止旧容器..."
        docker compose down 2>/dev/null || true
        docker stop traefik 2>/dev/null || true
        docker rm traefik 2>/dev/null || true
    fi

    # 检查本地是否已有镜像，有则跳过拉取
    if docker images | grep -q "traefik.*v3.0"; then
        echo "镜像 traefik:v3.0 已存在，跳过拉取"
    else
        echo "正在拉取 Traefik 镜像..."
        docker pull traefik:v3.0 || {
            echo -e "${YELLOW}尝试从国内镜像拉取...${NC}"
            docker pull m.daocloud.io/docker.io/library/traefik:v3.0
            docker tag m.daocloud.io/docker.io/library/traefik:v3.0 traefik:v3.0
        }
    fi

    docker compose up -d

    sleep 2
    if docker ps | grep -q "traefik"; then
        echo -e "${GREEN}✓ Traefik 启动成功${NC}"
        docker ps | grep traefik
    else
        echo -e "${RED}✗ Traefik 启动失败，请检查日志${NC}"
        docker logs traefik 2>&1 || true
        exit 1
    fi
}

# 主函数
main() {
    echo "========================================"
    echo "  Traefik 共享反向代理环境搭建脚本"
    echo "========================================"
    echo ""

    check_root
    check_docker
    create_network
    setup_traefik
    start_traefik

    echo ""
    echo "========================================"
    echo -e "${GREEN}Traefik 环境搭建完成!${NC}"
    echo "========================================"
    echo ""
    echo "配置目录: ${TRAEFIK_DIR}/"
    echo ""
    echo "常用命令:"
    echo "  docker ps                      - 查看运行中的容器"
    echo "  docker logs traefik            - 查看 Traefik 日志"
    echo "  cd ${TRAEFIK_DIR} && docker compose logs -f  - 实时查看日志"
    echo ""
}

# 执行主函数
main
