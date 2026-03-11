---
name: docker-compose-product-guide
description: Use when writing Docker Compose files to deploy products to this server environment, need to connect to databases, or configure Traefik routing
---

# Docker Compose Product Configuration Guide

## Overview

This guide defines how to write Docker Compose files for products that integrate with this server environment.

Core principle: **All services must join the `traefik-public` network and use Docker labels for Traefik routing, not port mappings.**

## When to Use

**Use this guide when:**

- Writing `docker-compose.yml` for a new product deployment
- Connecting an application to MongoDB, PostgreSQL, or MySQL
- Configuring Traefik routing for external access
- Setting up static site hosting with Nginx
- Troubleshooting deployment or database connection issues

**Don't use for:**
- Setting up the core infrastructure (use server-env setup scripts instead)
- Local development environments
- Docker Swarm or Kubernetes deployments

## Core Pattern

```yaml
services:
  app:
    image: your-app:latest
    container_name: your-app-name
    restart: unless-stopped
    environment:
      - NODE_ENV=production
    volumes:
      - app_data:/app/data
    networks:
      - traefik-public    # REQUIRED: Must use shared network
    labels:
      # REQUIRED: Traefik routing labels (if external access needed)
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`your-domain.com`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
      - "traefik.http.services.app.loadbalancer.server.port=3000"

volumes:
  app_data:
    name: your_app_data    # Named volume for persistence

networks:
  traefik-public:
    external: true         # Use existing shared network
```

## Quick Reference

| Task | Key Point |
|------|-----------|
| **Connect to database** | 1. Join `traefik-public` network<br>2. Use service name as hostname: `mongodb`, `postgres`, `mysql` |
| **MongoDB URI** | `mongodb://root:password@mongodb:27017/db?authSource=admin` |
| **PostgreSQL URL** | `postgresql://postgres:password@postgres:5432/db` |
| **MySQL URL** | `mysql://root:password@mysql:3306/db?charset=utf8mb4` |
| **Multiple domains** | `Host(\`www.example.com\`) \|\| Host(\`example.com\")` |
| **Path prefix** | `Host(\`api.example.com\") && PathPrefix(\`/v1\")` + `stripprefix` middleware |
| **HTTP→HTTPS redirect** | Add `-http` router with `redirect-to-https` middleware |
| **IP whitelist** | `traefik.http.middlewares.name.ipwhitelist.sourcerange=192.168.1.0/24` |
| **Basic auth** | Generate with `htpasswd -nbB admin password`, add `basicauth` middleware |

## Implementation

### Static Site Hosting (Nginx)

```yaml
services:
  web:
    image: nginx:alpine
    container_name: my-static-site
    restart: unless-stopped
    volumes:
      - ./dist:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.site.rule=Host(\`www.example.com\`)"
      - "traefik.http.routers.site.entrypoints=websecure"
      - "traefik.http.routers.site.tls.certresolver=letsencrypt"
      - "traefik.http.services.site.loadbalancer.server.port=80"

networks:
  traefik-public:
    external: true
```

### MongoDB Connection

**关键：加入网络，使用服务名连接**

```yaml
services:
  app:
    image: your-app:latest
    # 连接字符串配置方式灵活：
    # 方式1：在 docker-compose 环境变量中配置
    environment:
      - MONGO_URI=mongodb://root:password@mongodb:27017/myapp?authSource=admin
    # 方式2：在程序代码里直接写连接字符串
    # 方式3：分开配置，程序里拼装
    networks:
      - traefik-public  # 关键点：加入同一网络即可连通

networks:
  traefik-public:
    external: true
```

**说明：**
- 使用服务名 `mongodb` 作为 hostname（server-env 已部署）
- 连接字符串可以在 docker-compose 配，也可以在程序里直接写
- Traefik labels 是可选的（仅当需要外部访问时才加）

**Create database and user:**

```bash
docker exec -it mongodb mongosh -u root -p your_password

use your_database
db.createUser({
  user: "app_user",
  pwd: "app_password",
  roles: [{ role: "readWrite", db: "your_database" }]
})
```

### PostgreSQL Connection

**关键：加入网络，使用服务名连接**

```yaml
services:
  app:
    image: your-app:latest
    # 连接字符串配置方式灵活：
    # 方式1：在 docker-compose 环境变量中配置
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/myapp
    # 方式2：在程序代码里直接写连接字符串
    networks:
      - traefik-public  # 关键点：加入同一网络即可连通

networks:
  traefik-public:
    external: true
```

**Create database:**

```bash
docker exec -it postgres psql -U postgres

CREATE DATABASE your_database;
CREATE USER app_user WITH PASSWORD 'app_password';
GRANT ALL PRIVILEGES ON DATABASE your_database TO app_user;
```

### MySQL Connection

**关键：加入网络，使用服务名连接**

```yaml
services:
  app:
    image: your-app:latest
    # 连接字符串配置方式灵活：
    # 方式1：在 docker-compose 环境变量中配置
    environment:
      - DATABASE_URL=mysql://root:password@mysql:3306/myapp?charset=utf8mb4
    # 方式2：在程序代码里直接写连接字符串
    networks:
      - traefik-public  # 关键点：加入同一网络即可连通

networks:
  traefik-public:
    external: true
```

**Create database:**

```bash
docker exec -it mysql mysql -uroot -p

CREATE DATABASE your_database CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'app_user'@'%' IDENTIFIED BY 'app_password';
GRANT ALL PRIVILEGES ON your_database.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
```

### Security Headers

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.app.rule=Host(\`example.com\`)"
  - "traefik.http.routers.app.entrypoints=websecure"
  - "traefik.http.routers.app.tls.certresolver=letsencrypt"
  - "traefik.http.middlewares.security-headers.headers.stsSeconds=31536000"
  - "traefik.http.middlewares.security-headers.headers.stsIncludeSubdomains=true"
  - "traefik.http.middlewares.security-headers.headers.forceStsHeader=true"
  - "traefik.http.routers.app.middlewares=security-headers"
```

### Path Prefix with Stripping

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.api.rule=Host(\`api.example.com\") && PathPrefix(\`/v1\")"
  - "traefik.http.routers.api.entrypoints=websecure"
  - "traefik.http.routers.api.tls.certresolver=letsencrypt"
  - "traefik.http.services.api.loadbalancer.server.port=8080"
  - "traefik.http.middlewares.strip-api.stripprefix.prefixes=/v1"
  - "traefik.http.routers.api.middlewares=strip-api"
```

## Common Mistakes

| Mistake | Problem | Fix |
|---------|---------|-----|
| Using `ports:` mapping | Bypasses Traefik, no HTTPS | Use Traefik labels only |
| Wrong hostname for database | Connection refused | Use `mongodb`, `postgres`, `mysql` (not localhost/IP) |
| Missing `authSource=admin` | MongoDB auth fails | Add `?authSource=admin` to URI |
| Missing `external: true` on network | Creates isolated network | Add `external: true` |
| Not using named volumes | Data lost on recreate | Define `volumes:` with name |
| Using `latest` tag inconsistently | Version mismatches | Pin specific versions |

## Deployment Checklist

1. **Container configuration**
   - [ ] `container_name` is set
   - [ ] `restart: unless-stopped` is set
   - [ ] Service joins `traefik-public` network

2. **Database connection**
   - [ ] Hostname is service name (`mongodb`/`postgres`/`mysql`)
   - [ ] Password uses environment variable (not hardcoded)
   - [ ] For MongoDB: `authSource=admin` is in URI

3. **Traefik routing** (if external access needed)
   - [ ] `traefik.enable=true` label present
   - [ ] Router rule with Host() matcher
   - [ ] `entrypoints=websecure` for HTTPS
   - [ ] `tls.certresolver=letsencrypt` for auto-certs
   - [ ] Service port defined

4. **Data persistence**
   - [ ] Named volumes for data that must survive
   - [ ] Volume names are descriptive

## Troubleshooting

**Service not accessible:**
```bash
docker ps | grep your-app
docker logs traefik | grep your-app
docker network inspect traefik-public
```

**Database connection failed:**
```bash
# Check if service is enabled in .env
grep MONGO_ENABLED .env

# Test network connectivity
docker exec your-app ping mongodb

# Verify credentials
docker exec -it mongodb mongosh -u root -p
```

**HTTPS certificate issues:**
```bash
# Check Traefik logs
docker logs traefik | grep acme

# Verify ports are open
sudo netstat -tlnp | grep -E ':(80|443)'
```

## References

- [Traefik Docker Provider](https://doc.traefik.io/traefik/providers/docker/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [MongoDB Connection String](https://docs.mongodb.com/manual/reference/connection-string/)
