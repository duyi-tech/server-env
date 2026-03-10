# Traefik 共享反向代理环境搭建

## 架构说明

这是一个**共享反向代理层**架构，特点：
- Traefik 作为共享代理层，部署一次即可服务所有产品
- 各产品的代理配置写在各自的工程中，互不干扰
- 支持自动 HTTPS（Let's Encrypt）
- 新增产品时无需修改 Traefik 配置

目录结构规划：
```
/opt/
├── traefik/                    # 共享代理层
│   ├── docker-compose.yml
│   ├── traefik.yml
│   └── letsencrypt/            # 证书存储
└── products/                   # 各产品目录
    ├── blog/
    └── api/
```

---

## 第一步：创建共享网络

所有产品通信的基础，Traefik 和各产品通过此网络连接。

```bash
# 创建目录
sudo mkdir -p /opt/traefik/letsencrypt
cd /opt/traefik

# 创建 Docker 网络
sudo docker network create traefik-public

# 验证
sudo docker network ls | grep traefik-public
```

**说明**：
- 默认每个 Compose 会创建自己的私有网络，互相无法通信
- `traefik-public` 是一个公共桥接网络，所有产品加入此网络，Traefik 才能发现它们

---

## 第二步：配置 Docker 镜像加速（国内服务器）

编辑 Docker 配置文件：

```bash
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://m.daocloud.io",
    "https://你的阿里云镜像地址.mirror.aliyuncs.com"
  ]
}
EOF

# 重启 Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

# 验证配置
sudo docker info | grep -A 10 "Registry Mirrors"
```

---

## 第三步：启动 Traefik 基础版

### 3.1 创建 Traefik 配置文件

```bash
sudo tee /opt/traefik/traefik.yml << 'EOF'
api:
  dashboard: true
  insecure: true  # 临时开启方便调试，生产环境会关闭

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false  # 安全：默认不暴露容器
    network: traefik-public  # 使用我们创建的网络

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com  # 替换为你的邮箱
      storage: /letsencrypt/acme.json
      tlsChallenge: {}

log:
  level: INFO
EOF
```

### 3.2 创建 Docker Compose 文件

```bash
sudo tee /opt/traefik/docker-compose.yml << 'EOF'
version: '3.8'

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
      - "8080:8080"  # Dashboard 端口（生产环境会移除）
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
EOF
```

### 3.3 启动服务

```bash
cd /opt/traefik
sudo docker compose up -d
```

### 3.4 验证

```bash
# 查看容器状态
sudo docker ps | grep traefik

# 期望看到：
# - 状态为 Up
# - 端口映射了 0.0.0.0:80->80/tcp 和 0.0.0.0:8080->8080/tcp
```

访问 Dashboard：`http://你的服务器IP:8080/dashboard/`

---

## 第四步：部署第一个产品（验证模式）

在另一个目录创建第一个产品（模拟真实场景：产品是独立的，Traefik 是共享的）。

### 4.1 创建产品目录

```bash
sudo mkdir -p /opt/products/whoami
cd /opt/products/whoami
```

### 4.2 创建产品的 Docker Compose

```bash
sudo tee docker-compose.yml << 'EOF'
version: '3.8'

services:
  whoami:
    image: traefik/whoami  # 轻量级测试镜像
    container_name: whoami
    restart: unless-stopped
    networks:
      - traefik-public
    labels:
      # 关键配置：告诉 Traefik 暴露这个服务
      - "traefik.enable=true"
      # 路由规则
      - "traefik.http.routers.whoami.rule=Host(`whoami.yourdomain.com`)"
      - "traefik.http.routers.whoami.entrypoints=web"
      # HTTPS 路由
      - "traefik.http.routers.whoami-secure.rule=Host(`whoami.yourdomain.com`)"
      - "traefik.http.routers.whoami-secure.entrypoints=websecure"
      - "traefik.http.routers.whoami-secure.tls=true"
      - "traefik.http.routers.whoami-secure.tls.certresolver=letsencrypt"
      # HTTP 重定向到 HTTPS
      - "traefik.http.routers.whoami.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"

networks:
  traefik-public:
    external: true
EOF
```

### 4.3 启动产品

```bash
sudo docker compose up -d
```

### 4.4 验证

```bash
# 本地测试路由
curl -H "Host: whoami.yourdomain.com" http://localhost

# 期望看到：返回容器信息，包含 Hostname、IP 等
```

刷新 Dashboard（`http://IP:8080/dashboard/`），应该看到：
- HTTP Routers 区域出现 `whoami@docker`
- HTTP Services 区域出现 `whoami@docker`

---

## 第五步：生产环境配置（关闭 Dashboard）

### 5.1 停止现有 Traefik

```bash
cd /opt/traefik
sudo docker compose down
```

### 5.2 修改配置（移除 insecure 模式）

```bash
sudo tee /opt/traefik/traefik.yml << 'EOF'
api:
  dashboard: true
  insecure: false  # 关闭不安全入口

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https  # HTTP 自动跳转 HTTPS
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: traefik-public

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /letsencrypt/acme.json
      tlsChallenge: {}

log:
  level: WARN  # 生产环境减少日志
EOF
```

### 5.3 修改 Compose（移除 8080 端口）

```bash
sudo tee /opt/traefik/docker-compose.yml << 'EOF'
version: '3.8'

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
      # 8080 已移除（生产环境关闭 Dashboard 外部访问）
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./letsencrypt:/letsencrypt
    networks:
      - traefik-public

networks:
  traefik-public:
    external: true
EOF
```

### 5.4 启动生产环境配置

```bash
sudo docker compose up -d
```

### 5.5 验证

```bash
# 确认只映射了 80 和 443
sudo docker ps | grep traefik

# 测试 HTTPS
curl -v https://whoami.yourdomain.com
```

---

## 第六步：后续添加新产品

新产品只需在 `/opt/products/` 下创建目录，配置 labels 即可。

### 6.1 创建产品目录和配置

```bash
PROJECT_NAME="myapp"
DOMAIN="myapp.yourdomain.com"

sudo mkdir -p /opt/products/${PROJECT_NAME}
cd /opt/products/${PROJECT_NAME}

sudo tee docker-compose.yml << EOF
version: '3.8'

services:
  ${PROJECT_NAME}:
    image: your-image-name  # 替换为你的镜像
    container_name: ${PROJECT_NAME}
    restart: unless-stopped
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${PROJECT_NAME}.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${PROJECT_NAME}.entrypoints=web"
      - "traefik.http.routers.${PROJECT_NAME}.middlewares=https-redirect"
      - "traefik.http.routers.${PROJECT_NAME}-secure.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${PROJECT_NAME}-secure.entrypoints=websecure"
      - "traefik.http.routers.${PROJECT_NAME}-secure.tls=true"
      - "traefik.http.routers.${PROJECT_NAME}-secure.tls.certresolver=letsencrypt"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"

networks:
  traefik-public:
    external: true
EOF
```

### 6.2 启动产品

```bash
sudo docker compose up -d
```

### 6.3 配置 DNS

在域名服务商处添加 A 记录，将 `myapp.yourdomain.com` 指向服务器 IP。

### 6.4 验证

```bash
curl https://myapp.yourdomain.com
```

---

## 核心要点总结

1. **共享网络**：`traefik-public` 是 Traefik 和各产品通信的桥梁
2. **自动发现**：各产品通过 `labels` 声明路由，Traefik 自动识别
3. **配置隔离**：每个产品的路由配置写在各自的 `docker-compose.yml` 中
4. **自动 HTTPS**：配置 `tls.certresolver=letsencrypt` 即可自动申请证书
5. **HTTP 跳转 HTTPS**：通过 `middlewares` 配置自动跳转

---

## 常见问题

### 1. 拉取镜像超时

如果 `docker pull traefik:v3.0` 超时，手动从国内源拉取：

```bash
sudo docker pull m.daocloud.io/docker.io/library/traefik:v3.0
sudo docker tag m.daocloud.io/docker.io/library/traefik:v3.0 traefik:v3.0
```

### 2. 证书申请失败

确保：
- 域名 DNS 解析已指向服务器 IP
- 服务器 80/443 端口对公网开放
- 防火墙未阻拦

### 3. Dashboard 无法访问

生产环境 Dashboard 默认关闭（`insecure: false`），如需临时开启调试：

```bash
# 修改 traefik.yml 将 insecure 改为 true
# 修改 docker-compose.yml 添加 8080 端口映射
sudo docker compose up -d
```
