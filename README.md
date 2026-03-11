# Server Env - 一键搭建 Docker 化服务器环境

[![Docker](https://img.shields.io/badge/Docker-20.10+-blue.svg)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-2.0+-blue.svg)](https://docs.docker.com/compose/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

一个用于快速搭建生产级 Docker 化服务器环境的自动化脚本工程。通过简单的配置和一键执行，即可部署包含反向代理、数据库等完整的服务器环境。

## ✨ 特性

- 🚀 **一键部署** - 单条命令完成全部环境搭建
- 🔧 **配置集中** - 所有服务配置统一在 `.env` 文件中管理
- 🎛️ **灵活开关** - 每个服务都有独立的启用/禁用开关
- 💾 **数据持久化** - 使用 Docker Volume 存储数据，方便迁移
- 🔒 **安全可靠** - 服务仅在 Docker 内部网络暴露，不映射宿主机端口
- 🌐 **HTTPS 支持** - 内置 Traefik 反向代理，自动申请 Let's Encrypt 证书
- 🚀 **国内加速** - 自动尝试国内镜像源，解决拉取失败问题
- 📊 **资源限制** - 支持为每个服务设置内存限制

## 📦 包含服务

| 服务 | 版本 | 说明 |
|------|------|------|
| **Traefik** | v3.0 | 反向代理和负载均衡，自动 HTTPS |
| **MongoDB** | 6.0 | 文档型数据库 |
| **PostgreSQL** | 16 | 关系型数据库 |
| **MySQL** | 8.0 | 关系型数据库 |

## 🚀 快速开始

### 环境要求

- Linux 服务器（Ubuntu 20.04+、CentOS 7+ 等）
- root 或 sudo 权限
- 互联网连接

### 1. 克隆仓库

```bash
git clone https://github.com/yourusername/server-env.git
cd server-env
```

### 2. 配置环境变量

```bash
cp .env.example .env
nano .env  # 或使用你喜欢的编辑器
```

根据你的需求修改 `.env` 文件中的配置：

```bash
# Traefik 配置（反向代理）
TRAEFIK_EMAIL=your-email@example.com  # 用于申请 SSL 证书
TRAEFIK_HTTP_REDIRECT=true            # 是否开启 HTTP 自动跳转 HTTPS

# MongoDB 配置
MONGO_ENABLED=true
MONGO_ROOT_USERNAME=root
MONGO_ROOT_PASSWORD=your_secure_password_here

# PostgreSQL 配置
POSTGRES_ENABLED=true
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password_here
```

### 3. 执行安装

```bash
sudo ./setup.sh
```

脚本会自动完成以下步骤：
1. 安装 Docker 和 Docker Compose（如未安装）
2. 创建共享 Docker 网络 `traefik-public`
3. 部署 Traefik 反向代理
4. 根据配置启动启用的数据库服务

### 4. 验证安装

```bash
# 查看运行中的容器
docker ps

# 查看 Traefik 日志
docker logs traefik

# 查看 MongoDB 日志
docker logs mongodb
```

## ⚙️ 详细配置

### 配置说明

所有配置都在项目根目录的 `.env` 文件中统一管理：

```bash
# ========================================
# Traefik 配置
# ========================================
TRAEFIK_EMAIL=your_email              # Let's Encrypt 证书申请邮箱
TRAEFIK_NETWORK=traefik-public        # Docker 网络名称
TRAEFIK_LOG_LEVEL=INFO                # 日志级别：DEBUG, INFO, WARN, ERROR
TRAEFIK_HTTP_REDIRECT=false           # 是否开启 HTTP 重定向到 HTTPS

# ========================================
# MongoDB 配置
# ========================================
MONGO_ENABLED=true                    # true=启用, false=禁用
MONGO_VERSION=6.0                     # MongoDB 版本
MONGO_PORT=27017                      # 内部端口（不映射到宿主机）
MONGO_ROOT_USERNAME=root              # 管理员用户名
MONGO_ROOT_PASSWORD=your_password     # 管理员密码
MONGO_MEMORY_LIMIT=512m               # 内存限制

# ========================================
# PostgreSQL 配置
# ========================================
POSTGRES_ENABLED=true                 # true=启用, false=禁用
POSTGRES_VERSION=16                   # PostgreSQL 版本
POSTGRES_USER=postgres                # 管理员用户名
POSTGRES_PASSWORD=your_password       # 管理员密码
POSTGRES_MEMORY_LIMIT=512m            # 内存限制

# ========================================
# 数据目录（服务配置文件存放位置）
# ========================================
TRAEFIK_DIR=/opt/shared/traefik       # Traefik 配置目录
MONGO_DIR=/opt/shared/mongodb         # MongoDB 配置目录
POSTGRES_DIR=/opt/shared/postgres     # PostgreSQL 配置目录
MYSQL_DIR=/opt/shared/mysql           # MySQL 配置目录
```

### 服务开关说明

每个服务都有独立的启用/禁用开关，支持的值（不区分大小写）：
- `true`
- `on`
- `1`
- `y`
- `yes`

当设置为禁用（如 `false`）时，脚本会自动停止并删除该服务的容器（数据卷会保留，不会丢失数据）。

### 数据持久化

所有服务数据都存储在 Docker Volume 中：

```bash
# 查看所有数据卷
docker volume ls

# 主要数据卷
# - traefik_certs    : HTTPS 证书
# - mongodb_data     : MongoDB 数据
# - mongodb_config   : MongoDB 配置
# - mongodb_backup   : MongoDB 备份
# - postgres_data    : PostgreSQL 数据
```

## 🔌 服务访问

### 内部网络访问

所有服务都运行在 Docker 内部网络 `traefik-public` 中，其他容器可以通过服务名访问：

**MongoDB 连接字符串：**
```
mongodb://root:your_password@mongodb:27017/your_database?authSource=admin
```

**PostgreSQL 连接字符串：**
```
postgresql://postgres:your_password@postgres:5432/your_database
```

### 本地管理访问

如需在宿主机上直接连接数据库，请使用 `docker exec`：

```bash
# 进入 MongoDB shell
docker exec -it mongodb mongosh -u root -p your_password

# 进入 PostgreSQL shell
docker exec -it postgres psql -U postgres
```

### Traefik 管理面板

Traefik 自带 Dashboard，可以通过以下方式访问：

```bash
# 方法一：端口转发（推荐）
ssh -L 8080:localhost:8080 your-server-ip
# 然后在浏览器访问 http://localhost:8080

# 方法二：临时暴露端口（生产环境慎用）
# 修改 traefik.yml 添加 dashboard 配置
```

## 🔒 安全建议

1. **修改默认密码** - 务必在 `.env` 中设置强密码
2. **不暴露数据库端口** - 数据库服务默认不映射到宿主机端口
3. **使用防火墙** - 配置服务器防火墙，仅开放 80 和 443 端口
4. **定期备份** - 定期备份 Docker Volume 数据
5. **HTTPS 优先** - 建议开启 `TRAEFIK_HTTP_REDIRECT=true`

## 📋 常用命令

```bash
# 查看所有容器状态
docker ps

# 查看容器日志
docker logs <容器名>
docker logs -f <容器名>  # 实时跟踪

# 重启服务
cd /opt/shared/<服务名> && docker compose restart

# 停止服务
cd /opt/shared/<服务名> && docker compose down

# 启动服务
cd /opt/shared/<服务名> && docker compose up -d

# 查看数据卷
docker volume ls

# 查看数据卷详情
docker volume inspect <卷名>

# 重新运行安装脚本（会重新加载 .env 配置）
sudo ./setup.sh
```

## 💾 数据备份与迁移

### 备份数据卷

```bash
# 备份 MongoDB 数据
docker run --rm -v mongodb_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/mongodb_data.tar.gz -C /data .

# 备份 PostgreSQL 数据
docker run --rm -v postgres_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/postgres_data.tar.gz -C /data .

# 备份所有卷
./scripts/backup-all.sh  # 如果存在此脚本
```

### 恢复数据卷

```bash
# 恢复 MongoDB 数据
docker run --rm -v mongodb_data:/data -v $(pwd):/backup alpine \
    tar xzf /backup/mongodb_data.tar.gz -C /data

# 重启服务使恢复生效
cd /opt/shared/mongodb && docker compose restart
```

### 服务器迁移

1. 在旧服务器上备份所有数据卷
2. 将备份文件复制到新服务器
3. 在新服务器上安装 Docker 环境
4. 复制 `.env` 配置到新服务器
5. 运行 `sudo ./setup.sh` 部署服务
6. 恢复数据卷备份

## 🛠️ 故障排查

### 容器无法启动

```bash
# 查看容器日志
docker logs <容器名>

# 检查端口占用
netstat -tlnp | grep 80
netstat -tlnp | grep 443

# 检查 Docker 网络
docker network ls
docker network inspect traefik-public
```

### 镜像拉取失败

脚本会自动尝试国内镜像源，如果仍然失败：

```bash
# 手动配置 Docker 国内镜像
sudo nano /etc/docker/daemon.json
```

添加：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```

然后重启 Docker：
```bash
sudo systemctl restart docker
```

### 证书申请失败

- 确保 `TRAEFIK_EMAIL` 设置正确
- 确保服务器的 80 和 443 端口对外开放
- 检查域名 DNS 解析是否正确
- 查看 Traefik 日志：`docker logs traefik`

## 🏗️ 开发新产品

如果您要在此服务器环境上部署自己的应用，请参考 **[SKILL.md](SKILL.md)** 获取详细的 Docker Compose 配置指南。

**SKILL.md 包含：**
- 📄 **基础模板** - 适配本环境的 Docker Compose 结构
- 🌐 **静态页面托管** - Nginx 配置和域名绑定
- 🍃 **MongoDB 集成** - 连接字符串配置和数据库创建
- 🐘 **PostgreSQL 集成** - Django 等框架的配置示例
- 🐬 **MySQL 集成** - WordPress 等应用的配置示例
- 🔒 **安全配置** - HTTPS、IP 白名单、基本认证等

### 快速示例

部署一个静态网站：

```yaml
services:
  web:
    image: nginx:alpine
    container_name: my-site
    volumes:
      - ./dist:/usr/share/nginx/html:ro
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-site.rule=Host(`www.example.com`)"
      - "traefik.http.routers.my-site.entrypoints=websecure"
      - "traefik.http.routers.my-site.tls.certresolver=letsencrypt"
      - "traefik.http.services.my-site.loadbalancer.server.port=80"

networks:
  traefik-public:
    external: true
```

> **注意**：更多详细配置（数据库连接、安全配置等）请查看 [SKILL.md](SKILL.md)。

## 📝 目录结构

```
server-env/
├── .env                    # 配置文件（你需要创建）
├── .env.example            # 配置示例文件
├── setup.sh                # 主入口脚本
├── README.md               # 本文件
├── SKILL.md                # 产品适配指南（开发新产品必看）
├── AGENTS.md               # 工程规范说明
├── basic-env/              # 基础环境搭建
│   ├── setup.sh
│   └── docker/
└── docker/                 # Docker 服务
    ├── setup.sh            # Docker 服务总入口
    ├── traefik/            # 反向代理
    │   └── setup.sh
    ├── mongodb/            # MongoDB 数据库
    │   └── setup.sh
    ├── postgres/           # PostgreSQL 数据库
    │   └── setup.sh
    └── mysql/              # MySQL 数据库
        └── setup.sh
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

[MIT License](LICENSE)

## 📞 支持

如果你遇到问题：

1. 查看本 README 的故障排查部分
2. 查看 [AGENTS.md](AGENTS.md) 了解工程规范
3. 查看 [SKILL.md](SKILL.md) 了解如何开发新产品
4. 提交 Issue 到本仓库

---

**注意：** 本工程适用于生产环境部署，请在部署前仔细阅读配置说明，确保密码和邮箱等敏感信息设置正确。
