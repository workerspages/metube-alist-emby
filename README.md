# MeTube + qBittorrent + Alist + Emby All-in-One

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
| `/qbittorrent/` | qBittorrent | BT/PT 下载器 |
| `/alist/` | Alist | 网盘管理 |
| `/debug/` | Alist | 诊断面板 |

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
| `/media/alist` | Alist 网盘通过 rclone 挂载，作为 Emby 媒体源 |
| `/config` | 所有服务配置数据 |

## 初始配置

### 1. 配置 Alist

通过环境变量 `ALIST_ADMIN_PASS` 设置管理员密码（适配 PaaS 无终端环境）：

```bash
docker run -d --name media-center --privileged \
  -p 8080:8080 \
  -e ALIST_ADMIN_PASS=your_password \
  -e ALIST_USER=admin \
  -e ALIST_PASS=your_password \
  -v ./downloads:/downloads \
  -v ./config:/config \
  ghcr.io/workerspages/metube-alist-emby:latest
```

> `ALIST_ADMIN_PASS` — Alist 管理员登录密码
> `ALIST_USER` / `ALIST_PASS` — rclone WebDAV 挂载认证（通常与管理员相同）

访问 `/alist/` 登录，在**存储**页面添加网盘驱动。

### 2. rclone 挂载（Alist → Emby）

Alist 网盘通过 rclone WebDAV 自动挂载到 `/media/alist`，Emby 可直接读取。

### 3. 配置 Emby

访问 `/web/` 完成设置向导，添加媒体库选择：
- `/media/metube` — MeTube 下载的视频（自动链接自 `/downloads`）
- `/media/alist` — Alist 挂载的网盘文件

注意：
纯手动输入（不要在下面的列表中找目录，找不到的）
直接点击输入框。
准确输入 /downloads 或 /media/metube（两个路径现在都是通的）。
重要：输入完毕后，仔细检查光标位置，确保结尾绝对没有哪怕一个空格！
点击输入框右侧的放大镜（搜索）图标，或者直接点击下方的绿色“确定”按钮。

插件目录：
`/opt/emby-server/system/plugins/`

### MeTube

访问 `/metube/`，粘贴链接下载视频，自动出现在 Emby 媒体库。

## 环境变量

所有 MeTube、Alist、Emby 原项目的官方环境变量均可直接通过 `docker run -e` 或 `docker-compose.yml` 传入。

### 容器专用变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ALIST_ADMIN_PASS` | _(空)_ | Alist 管理员密码（每次启动时设置） |
| `ALIST_USER` | `admin` | rclone WebDAV 认证用户名 |
| `ALIST_PASS` | _(空)_ | rclone WebDAV 认证密码 |
| `ALIST_DATA` | `/config/alist` | Alist 数据目录 |
| `EMBY_PROGRAMDATA` | `/config/emby` | Emby 数据目录 |

### MeTube 官方变量（可直接使用）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOWNLOAD_DIR` | `/downloads` | 下载目录 |
| `STATE_DIR` | `/downloads/.metube` | 状态目录 |
| `TEMP_DIR` | `/downloads` | 临时目录 |
| `YTDL_OPTIONS` | `{}` | yt-dlp 选项 (JSON) |
| `OUTPUT_TEMPLATE` | `%(title)s.%(ext)s` | 输出文件名模板 |
| `DARK_MODE` | `true` | 深色模式 |

> 更多 MeTube 变量见 [MeTube 官方文档](https://github.com/alexta69/metube#environment-variables)

### 被锁定的变量（不可更改）

| 变量 | 锁定值 | 原因 |
|------|--------|------|
| `URL_PREFIX` | `/metube/` | Caddy 路由依赖此路径 |
| MeTube `PORT` | `8081` | 内部端口，Caddy 转发用 |

## 技术栈

| 组件 | 用途 |
|------|------|
| [Emby](https://emby.media/) | 媒体服务器 |
| [MeTube](https://github.com/alexta69/metube) | yt-dlp Web 下载器 |
| [qBittorrent EE](https://github.com/c0re100/qBittorrent-Enhanced-Edition) | BT/PT 增强版下载客户端 |
| [Alist](https://github.com/AlistGo/alist) | 网盘挂载工具 |
| [rclone](https://rclone.org/) | WebDAV → 本地文件系统挂载 |
| [Caddy](https://caddyserver.com/) | 反向代理 |
| [Supervisord](http://supervisord.org/) | 进程管理 |

## License

MIT

