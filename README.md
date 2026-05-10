# MeTube + qBittorrent + Alist + Emby All-in-One

[![Build and Push](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml)

单容器部署 **Emby 媒体服务器** + **MeTube 视频下载器** + **Alist 网盘挂载** + **rclone WebDAV**，适用于 PaaS 平台。

## 架构

```
+-----------------------------------------------------------------------------------+
|                          Single Container (supervisord)                           |
|                                                                                   |
|     +----------+                                                                  |
|     |  Caddy   | <- :8080 (Single External Port)                                  |
|     |  Proxy   |                                                                  |
|     +----+-----+                                                                  |
|          |                                                                        |
|     +----+-----+-----------+-----------+----------+--------------------+--------+ |
|     |    V     |     V     |     V     |    V     |         V          |   V    | |
|     |    /     |  /emby/*  | /metube/* | /alist/* | /metatube-server/* |/rclone/| |
|     |  Portal  |   Emby    |  MeTube   |  Alist   |  MetaTube Server   | rclone | |
|     |          |   :8096   |   :8081   |  :5244   |       :8083        | :8085  | |
|     +----------+-----------+-----------+----------+--------------------+--------+ |
|                                                                                   |
|     Shared Directories: /media, /config                                           |
+-----------------------------------------------------------------------------------+
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
  -v ./media:/media \
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
| `/metatube-server/` | MetaTube Server | 刮削元数据服务器 |
| `/rclone/` | rclone WebDAV | WebDAV 文件服务（默认服务 `/media`）|
| `/debug/` | Alist/Emby | 诊断面板 |

## 镜像来源

| 平台 | 地址 |
|------|------|
| GHCR | `ghcr.io/workerspages/metube-alist-emby:latest` |
| Docker Hub | `docker.io/workerspages/metube-alist-emby:latest` |

支持架构：`linux/amd64`、`linux/arm64`

## 数据持久化

| 容器路径 | 说明 |
|---------|------|
| `/media` | 媒体源根目录（包含 MeTube、qBittorrent 和 Alist 数据） |
| `/media/alist` | Alist 网盘挂载，作为 Emby 媒体源 |
| `/media/metube` | MeTube 下载的数据，作为 Emby 媒体源 |
| `/media/qbittorrent` | qBittorrent 下载的数据，作为 Emby 媒体源 |
| `/config` | 所有服务配置数据 |

---
<details>
<summary>===== 单卷映射子目录 =====</summary>


### 解决方案：单卷映射子目录

将持久卷挂载到一个统一的父目录（如 `/data`），然后在容器内通过**软链接**将 `/media` 和 `/config` 指向该卷下的子目录。

#### 方案一：修改 entrypoint.sh（推荐）

在 [entrypoint.sh](/entrypoint.sh) 开头加入软链接初始化逻辑：

```bash
#!/bin/bash
set -e

# ==== 单卷多目录兼容逻辑 ====
DATA_ROOT="${PERSISTENT_ROOT:-/data}"
mkdir -p "${DATA_ROOT}/media" "${DATA_ROOT}/config"
if [ ! -L /media ]; then rm -rf /media && ln -s "${DATA_ROOT}/media" /media; fi
if [ ! -L /config ]; then rm -rf /config && ln -s "${DATA_ROOT}/config" /config; fi
# ==== 结束 ====

# 原有逻辑继续...
```

PaaS 平台只需挂载 **一个持久卷到 `/data`**。

#### 方案二：修改 Dockerfile，构建时预置软链接

```dockerfile
RUN mkdir -p /data/media /data/config \
    && ln -sf /data/media /media \
    && ln -sf /data/config /config
```

#### PaaS 配置对照

| 原 docker-compose 挂载 | PaaS 单卷方案 |
|---|---|
| `./media:/media` | 持久卷 → `/data`，软链 `/media` → `/data/media` |
| `./config:/config` | 持久卷 → `/data`，软链 `/config` → `/data/config` |

</details>

---

## 初始配置

### 1. ☁️ 配置 Alist

通过环境变量 `ALIST_ADMIN_PASS` 设置管理员密码（适配 PaaS 无终端环境）：

```bash
docker run -d --name media-center \
  -p 8080:8080 \
  -e ALIST_ADMIN_PASS=your_password \
  -v ./media:/media \
  -v ./config:/config \
  ghcr.io/workerspages/metube-alist-emby:latest
```

访问 `/alist/` 登录，在**存储**页面添加网盘驱动。

#### 默认登录信息：
> 用户名：`admin` 密码：`adminadmin`

### 2. 📺 配置 Emby

访问 `/web/` 完成设置向导，添加媒体库选择：
- `/media/alist` — Alist 挂载的网盘文件
- `/media/metube` — MeTube 下载的视频
- `/media/qbittorrent` — qBittorrent 下载的视频

注意：纯手动输入路径，不要在列表中搜索（找不到）。确保结尾没有多余空格，然后点放大镜图标或绿色"确定"按钮。

插件目录：`/opt/emby-server/system/plugins/`

#### Emby 客户端连接方法：
Emby 客户端只需填入**基础域名**，不要带 `/web/` 后缀：
> `https://your-domain.com`

#### 默认登录信息：
> 用户名：`root` 密码：`空`

### 3. ⬇️ 配置 MeTube

访问 `/metube/`，粘贴链接下载视频，自动出现在 Emby 媒体库。

#### 默认登录信息：
> 用户名：`空` 密码：`空`

### 4. 🧲 配置 qBittorrent

访问 `/qbittorrent/`，粘贴链接下载视频，自动出现在 Emby 媒体库。

#### 默认登录信息：
> 用户名：`admin` 密码：`admin`

### 5. 📂 配置 rclone WebDAV

rclone 在本项目中**仅作为 WebDAV 服务端**，无需任何 `rclone.conf`。默认将 `/media` 对外暴露，开箱即用。

#### 开启认证（强烈建议）

```yaml
- RCLONE_WEBDAV_USER=myuser
- RCLONE_WEBDAV_PASS=mypassword
```

#### WebDAV 客户端连接地址

```
http://localhost:8080/rclone/
```

### 6. 🔄 Emby 自动扫描

容器内置 `emby-scan-watcher` 进程，利用 `inotifywait` 实时监听 `/media` 目录，当 MeTube 或 qBittorrent 下载完成时自动通知 Emby 刷新媒体库。

**启用方式：**
1. 在 Emby 后台选择 **设置 → 高级 → API 密钒** 创建一个 API Key
2. 在环境变量中设置：

```yaml
- EMBY_API_KEY=your_api_key_here
```

**工作机制：**
- 使用 `inotifywait` 实时监听，有 **30 秒防抖**避免下载中频繁触发
- `EMBY_API_KEY` 为空时静默跳过，不影响其他服务

## 安全建议

> ⚠️ 容器启动时会检测以下安全风险并打印警告：

| 风险项 | 建议 |
|------|------|
| `ALIST_ADMIN_PASS` 为默认密码 | 请修改为强密码 |
| `RCLONE_WEBDAV_PASS` 未设置 | WebDAV 允许匿名访问，公网环境建议设置 |
| 无 HTTPS | 如有域名，将 `Caddyfile` 中 `:8080` 改为实际域名即自动开启 HTTPS |

## 环境变量

所有 MeTube、Alist、Emby 原项目的官方环境变量均可直接通过 `docker run -e` 或 `docker-compose.yml` 传入。

### 容器专用变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ALIST_ADMIN_PASS` | _(空)_ | Alist 管理员密码（每次启动时设置） |
| `ALIST_DATA` | `/config/alist` | Alist 数据目录 |
| `EMBY_PROGRAMDATA` | `/config/emby` | Emby 数据目录 |
| `EMBY_API_KEY` | _(空)_ | Emby API 密钒，用于自动触发媒体库扫描 |
| `METATUBE_SERVER_TOKEN` | _(空)_ | MetaTube Server 访问 Token |
| `RCLONE_WEBDAV_REMOTE` | `/media` | WebDAV 服务的本地目录路径 |
| `RCLONE_WEBDAV_PORT` | `8085` | rclone WebDAV 内部监听端口 |
| `RCLONE_WEBDAV_USER` | _(空)_ | WebDAV 认证用户名，空则匿名可访问 |
| `RCLONE_WEBDAV_PASS` | _(空)_ | WebDAV 认证密码，空则匿名可访问 |

### MeTube 官方变量（可直接使用）

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DOWNLOAD_DIR` | `/media/metube` | 下载目录 |
| `STATE_DIR` | `/media/metube/.metube` | 状态目录 |
| `TEMP_DIR` | `/media/metube` | 临时目录 |
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
| [MetaTube Server](https://github.com/metatube-community/metatube-server) | 刮削元数据服务器 |
| [rclone](https://rclone.org/) | WebDAV 文件服务端 |
| [Caddy](https://caddyserver.com/) | 反向代理 |
| [Supervisord](http://supervisord.org/) | 进程管理 |
| [inotify-tools](https://github.com/inotify-tools/inotify-tools) | 文件系统实时监听 |

## License

MIT
