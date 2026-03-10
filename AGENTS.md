# 服务端环境搭建

这是一个用于自动搭建服务器环境的工程，通过脚本一键部署完整的 Docker 化服务器环境。

## 目录结构

```
server-env/
├── basic-env/          # 基础环境搭建，包括安装必要的软件和配置环境变量
│   └── setup.sh
├── docker/             # Docker 容器服务
│   ├── setup.sh        # 总入口脚本，依次调用各个服务的 setup.sh
│   ├── traefik/        # 共享反向代理
│   │   └── setup.sh
│   └── mongodb/        # 数据库服务
│       └── setup.sh
├── .env                # 所有服务的配置集中在这里
└── AGENTS.md           # 本文件，工程规范说明
```

## 设计原则

### 1. 配置集中管理
- **所有服务配置都集中在根目录 `.env` 文件中**
- 子服务脚本通过 `source` 或 `export` 加载 `.env`
- 配置项命名规范：`{服务名}_{配置项}`，如 `MONGO_VERSION`、`TRAEFIK_EMAIL`

### 2. 启用/禁用开关
- 每个服务必须支持启用/禁用开关：`{服务名}_ENABLED`
- 支持的值（不区分大小写）：`true`、`on`、`1`、`y`、`yes`
- 禁用时的行为：检查并停止现有容器，不做其他操作
- 开关判断函数需兼容 macOS Bash 3.2：
  ```bash
  is_service_enabled() {
      local enabled_lower=$(echo "$SERVICE_ENABLED" | tr '[:upper:]' '[:lower:]')
      case "$enabled_lower" in
          true|on|1|y|yes) return 0 ;;
          *) return 1 ;;
      esac
  }
  ```

### 3. 数据持久化
- **使用 Docker Volume 而非宿主机目录绑定**
- 命名规范：`{服务名}_{用途}`，如 `mongodb_data`、`traefik_certs`
- Volume 用于：数据库数据、证书、配置文件等需要迁移的内容
- 不需要 Volume 的：日志（输出到 stdout）、临时文件

### 4. 网络架构
- 使用共享网络 `traefik-public` 作为所有服务的通信基础
- 各服务脚本负责检查并创建网络（如不存在）
- 服务间通过服务名在内部网络通信，不暴露宿主机端口（除非必要）

### 5. 脚本规范

#### 标准结构
```bash
#!/bin/bash
set -e

# 1. 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 2. 加载 .env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
if [ -f "${PROJECT_ROOT}/.env" ]; then
    export $(cat "${PROJECT_ROOT}/.env" | grep -v '^#' | xargs)
fi

# 3. 设置默认值（兼容 .env 中未定义的情况）
SERVICE_ENABLED="${SERVICE_ENABLED:-true}"
SERVICE_VERSION="${SERVICE_VERSION:-latest}"

# 4. 功能函数
# - check_root()        # 检查 root 权限
# - check_docker()      # 检查 Docker 安装
# - check_network()     # 检查/创建共享网络
# - setup_service()     # 生成配置文件
# - start_service()     # 启动容器
# - stop_service()      # 停止容器（用于禁用场景）

# 5. 主函数
main() {
    # 判断是否启用服务
    if is_service_enabled; then
        # 正常安装流程
    else
        # 停止容器（如果存在）
    fi
}

main
```

#### 生成 docker-compose.yml
- 必须包含：服务定义、volumes、networks
- 使用 EOF 生成文件，包含变量替换
- 必须指定 container_name，方便管理

### 6. 国内镜像加速
- 拉取镜像失败时，自动尝试国内镜像源
- 常用国内源：`m.daocloud.io/docker.io/library/{镜像名}`
- 拉取后需要 `docker tag` 重命名回原镜像名

### 7. 日志输出
- 所有服务日志输出到 stdout（Docker 默认）
- 查看方式：`docker logs {容器名}` 或 `docker compose logs -f`
- 禁止写入宿主机日志文件

## 添加新服务的步骤

1. **创建目录**：`docker/{服务名}/`

2. **编写 setup.sh**：
   - 复制现有服务脚本作为模板
   - 修改服务名和配置变量
   - 实现启用/禁用逻辑
   - 生成正确的 docker-compose.yml

3. **更新 .env**：
   - 添加 `{服务名}_ENABLED=true`
   - 添加服务所需的配置项

4. **更新总入口**：
   - 在 `docker/setup.sh` 中添加对新脚本的调用

## .env 配置示例

```bash
# 全局配置
TRAEFIK_NETWORK=traefik-public

# MongoDB 配置
MONGO_ENABLED=true
MONGO_VERSION=6.0
MONGO_ROOT_USERNAME=root
MONGO_ROOT_PASSWORD=your_secure_password
MONGO_MEMORY_LIMIT=512m

# Traefik 配置
TRAEFIK_ENABLED=true
TRAEFIK_EMAIL=your@email.com
TRAEFIK_LOG_LEVEL=INFO

# 后续添加更多服务...
```

## 迁移指南

需要备份的 Docker Volume：
- `traefik_certs` - HTTPS 证书
- `mongodb_data` - 数据库数据
- `mongodb_config` - 数据库配置
- `mongodb_backup` - 备份文件

导出命令：
```bash
docker run --rm -v {卷名}:/data -v $(pwd):/backup alpine \
    tar czf /backup/{卷名}.tar.gz -C /data .
```

导入命令：
```bash
docker run --rm -v {卷名}:/data -v $(pwd):/backup alpine \
    tar xzf /backup/{卷名}.tar.gz -C /data
```
