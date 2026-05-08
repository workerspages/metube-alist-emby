# MeTube + Alist + Emby All-in-One

[![Build and Push](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml)

单容器部署 **Emby 媒体服务器** + **MeTube 视频下载器** + **Alist 网盘挂载**，适用于 PaaS 平台。

## 架构

```
┌──────────────────────────────────────────────────┐
│            单容器 (supervisord)                    │
│                                                   │
│   ┌─────────┐                                     │
│   │  Caddy   │ ← :8080 (唯一对外端口)              │
│   │  反向代理 │                                    │
│   └────┬─────┘                                    │
│        │                                          │
│   ┌────┼──────────┬──────────┬──────────┐        │
│   │    ▼          ▼          ▼          ▼        │
│   │    /       /emby/*   /metube/*  /alist/*     │
│   │  门户页    Emby       MeTube     Alist       │
│   │          :8096       :8081      :5244        │
│   └─────────────────────────────────────────┘    │
│                                                   │
│   共享目录: /downloads, /config                    │
└──────────────────────────────────────────────────┘
```

## 快速开始

### Docker Compose（推荐）

```bash
git clone https://github.com/workerspages/metube-alist-emby.git
cd metube-alist-emby
docker compose up -d
```

### Docker Run

```bash
docker run -d \
  --name media-center \
  -p 8080:8080 \
  -v ./downloads:/downloads \
  -v ./config:/config \
  ghcr.io/workerspages/metube-alist-emby:latest
```

### 访问服务

打开 `http://localhost:8080` 即可看到门户页面。

| 路径 | 服务 | 说明 |
|------|------|------|
| `/` | 门户 | 导航页面 |
| `/emby/web/` | Emby | 媒体服务器 |
| `/metube/` | MeTube | 视频下载器 |
| `/alist/` | Alist | 网盘管理 |

## 镜像来源

| 平台 | 地址 |
|------|------|
| GHCR | `ghcr.io/workerspages/metube-alist-emby:latest` |
| Docker Hub | `docker.io/workerspages/metube-alist-emby:latest` |

支持架构：`linux/amd64`、`linux/arm64`

## 数据持久化

| 容器路径 | 说明 |
|---------|------|
| `/downloads` | MeTube 下载文件，同时作为 Emby 媒体源 |
| `/config` | 所有服务配置数据 |
| `/config/emby` | Emby 配置和数据库 |
| `/config/alist` | Alist 配置和数据 |

## 初始配置

### Emby

首次访问 `/emby/web/` 完成设置向导。添加媒体库时选择 `/downloads` 目录。

### MeTube

访问 `/metube/`，粘贴视频链接即可下载。

### Alist

1. 查看初始管理员密码：
   ```bash
   docker exec media-center cat /config/alist/admin_password.txt 2>/dev/null || \
   docker logs media-center 2>&1 | grep -i password
   ```
2. 访问 `/alist/` 并登录
3. 在存储页面添加网盘驱动

## PaaS 部署

本项目专为 PaaS 平台设计：
- **单容器**：所有服务打包在一个镜像中
- **单端口**：仅暴露 8080 端口（Cloudflare 兼容）
- **Caddy 反代**：自动路径分发到各服务

## 技术栈

| 组件 | 用途 |
|------|------|
| [Emby](https://emby.media/) | 媒体服务器 |
| [MeTube](https://github.com/alexta69/metube) | yt-dlp Web 下载器 |
| [Alist](https://github.com/AlistGo/alist) | 网盘挂载工具 |
| [Caddy](https://caddyserver.com/) | 反向代理 |
| [Supervisord](http://supervisord.org/) | 进程管理 |

## License

MIT
