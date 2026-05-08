# MeTube + Alist + Emby

[![Validate and Release](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml)

一键部署 **Emby 媒体服务器** + **MeTube 视频下载器** + **Alist 网盘挂载** 的 Docker Compose 项目。

## 架构

```
┌─────────────────────────────────────────────────┐
│                  Docker Network                  │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │  MeTube   │  │  Alist   │  │   Emby   │      │
│  │  :8880    │  │  :2052   │  │  :8080   │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │              │             │             │
│       ▼              ▼             │             │
│  ./downloads    ./alist-data ──────┘             │
│       │                            │             │
│       └────────────────────────────┘             │
│            共享媒体目录 (只读)                     │
└─────────────────────────────────────────────────┘
```

- **MeTube** 下载视频到 `./downloads`，Emby 以只读方式挂载
- **Alist** 挂载网盘数据到 `./alist-data`，Emby 以只读方式挂载
- **Emby** 从两个目录读取媒体文件提供流媒体服务

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/workerspages/metube-alist-emby.git
cd metube-alist-emby
```

### 2. 配置环境变量（可选）

```bash
cp .env.example .env
# 根据需要编辑 .env 文件
```

### 3. 启动服务

```bash
docker compose up -d
```

### 4. 访问服务

| 服务 | 地址 | 说明 |
|------|------|------|
| Emby | `http://localhost:8080` | 媒体服务器 Web UI |
| MeTube | `http://localhost:8880` | 视频下载器 Web UI |
| Alist | `http://localhost:2052` | 网盘管理 Web UI |

## 端口说明

所有端口均兼容 Cloudflare HTTP 代理：

| 服务 | 宿主机端口 | 容器端口 | 环境变量 |
|------|-----------|---------|----------|
| Emby | 8080 | 8096 | `EMBY_PORT` |
| MeTube | 8880 | 8081 | `METUBE_PORT` |
| Alist | 2052 | 5244 | `ALIST_PORT` |

## 服务配置

### Emby

首次启动后访问 `http://localhost:8080` 完成初始设置向导。添加媒体库时选择：
- `/media/downloads` — MeTube 下载的视频
- `/media/alist` — Alist 挂载的网盘文件

### MeTube

访问 `http://localhost:8880`，粘贴视频链接即可下载。下载的文件会自动出现在 Emby 媒体库中。

### Alist

1. 访问 `http://localhost:2052`
2. 设置管理员密码：
   ```bash
   docker exec -it alist ./alist admin set YOUR_PASSWORD
   ```
3. 登录后在 **存储** 页面添加网盘驱动（阿里云盘、Google Drive、OneDrive 等）
4. 挂载的文件会自动出现在 Emby 媒体库中

## 数据目录

| 目录 | 说明 |
|------|------|
| `./emby-config/` | Emby 配置和数据库 |
| `./downloads/` | MeTube 下载文件 |
| `./alist-data/` | Alist 配置和数据 |

## 更新服务

```bash
docker compose pull
docker compose up -d
```

## 停止服务

```bash
docker compose down
```

## GitHub Actions

项目使用 GitHub Actions 自动化：
- **推送到 main**：验证 `docker-compose.yml` 语法
- **推送 tag**（如 `v1.0.0`）：验证配置并创建 GitHub Release

## License

MIT
