# MeTube + qBittorrent + Alist + Emby All-in-One

[![Build and Push](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/workerspages/metube-alist-emby/actions/workflows/docker-publish.yml)

单容器部署 **Emby 媒体服务器** + **MeTube 视频下载器** + **Alist 网盘挂载** + **qBittorrent BT/PT 下载** + **rclone WebDAV**，适用于 PaaS 平台。

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
|  /  /emby/*  /metube/*  /alist/*  /qbittorrent/*  /metatube-server/*  /rclone/*   |
|  Portal  Emby   MeTube    Alist    qBittorrent      MetaTube Server    rclone     |
|          :8096   :8081    :5244       :8082              :8083          :8085     |
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
  -e ALIST_ADMIN_PASS=your_password \
  -e METUBE_AUTH_PASS=your_password \
  -e DEBUG_AUTH_PASS=your_password \
  -v ./media:/media \
  -v ./config:/config \
  ghcr.io/workerspages/metube-alist-emby:latest
```

### 访问服务

打开 `http://localhost:8080` 即可看到门户页面。

| 路径 | 服务 | 认证 | 说明 |
|------|------|---------|------|
| `/` | 门户 | 无 | 导航页面 |
| `/emby/web/` | Emby | 自带用户系统 | 媒体服务器 |
| `/metube/` | MeTube | Basic Auth | 视频下载器 |
| `/qbittorrent/` | qBittorrent | 自带用户系统 | BT/PT 下载器 |
| `/alist/` | Alist | 自带用户系统 | 网盘管理 |
| `/metatube-server/` | MetaTube Server | Token（可选） | 刷削元数据服务器 |
| `/rclone/` | rclone WebDAV | Basic Auth | WebDAV 文件服务 |
| `/debug/` | 诊断面板 | Basic Auth | STRM 同步调试 |

## 镜像来源

| 平台 | 地址 |
|------|------|
| GHCR | `ghcr.io/workerspages/metube-alist-emby:latest` |
| Docker Hub | `docker.io/workerspages/metube-alist-emby:latest` |

支持架构：`linux/amd64`、`linux/arm64`

## 数据持久化

| 容器路径 | 说明 |
|---------|------|
| `/media` | 媒体源根目录 |
| `/media/alist` | Alist 网盘挂载，作为 Emby 媒体源 |
| `/media/metube` | MeTube 下载的数据 |
| `/media/qbittorrent` | qBittorrent 下载的数据 |
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

通过环境变量 `ALIST_ADMIN_PASS` 设置管理员密码（适配 PaaS 无终端环境）。

访问 `/alist/` 登录，在**存储**页面添加网盘驱动。

> 默认登录：用户名: `admin` 密码: `adminadmin`

### 2. 📺 配置 Emby

访问 `/web/` 完成设置向导，添加媒体库选择：
- `/media/alist` — Alist 挂载的网盘文件
- `/media/metube` — MeTube 下载的视频
- `/media/qbittorrent` — qBittorrent 下载的视频

> 注意：纯手动输入路径，不要在列表中搜索。确保结尾没有多余空格。

- 插件目录：`/opt/emby-server/system/plugins/`
- Emby 的安装目录：`/opt/emby-server`


> `https://your-domain.com`

> 默认登录：用户名: `root` 密码:`空`

#### 💡 Emby 性能与防崩溃优化（PaaS 部署必看）
在资源有限的 PaaS 平台（如 Zeabur、Koyeb、Railway）部署时，强烈建议进行以下设置，防止因内存溢出（OOM）或 CPU 占满导致容器无限重启：

1. **关闭视频转码（防止 CPU 卡死）**
   - 进入 **设置 -> 用户 -> 点击自己的头像 -> 媒体播放**。
   - 取消勾选 **“如有必要，在媒体播放期间允许视频转码为兼容格式”** 和音频转码选项。
   - 取消勾选 **“允许下载需要转码的媒体”** 和 **“允许媒体转换”**。
   - *（注：可保留“允许更改容器格式”，因为串流/Remux 几乎不消耗 CPU。）*
2. **关闭耗性能的图片提取（防 OOM 内存溢出宕机）**
   - 进入 **设置 -> 媒体库 -> 点击对应的库 -> 管理库 -> 展开高级选项**。
   - 将 **“章节图像提取 (Chapter image extraction)”** 设为 **从不 (Never)**。
   - 将 **“视频预览缩略图 (Video preview thumbnails)”** 设为 **从不 (Never)**。（这是最耗内存的服务器杀手）
   - **保留开启 “Screen Grabber / Image Capture”**，以确保无刮削数据的视频依然能有一张自动截图作为封面。
3. **精准配置刮削器（秒出海报）**
   - 若您主要播放特定资源（如使用 MetaTube），请在库设置的“图像获取器”列表中，**仅勾选 MetaTube 和 Image Capture**，并取消勾选 TheMovieDb、TheTVDB 等常规电影刮削器。这能节约大量无用的网络请求，极大加快扫描入库速度。

### 3. ⬇️ 配置 MeTube

MeTube 通过 Caddy **Basic Auth** 保护，通过环境变量设置密码：

```yaml
environment:
  - METUBE_AUTH_PASS=your_password  # 用户名固定为: `admin`
```

访问 `/metube/`，粘贴链接下载视频。

### 4. 🧺 配置 qBittorrent

访问 `/qbittorrent/`，默认登录信息：
> 用户名: `admin` 密码: `adminadmin`

### 5. 📂 配置 rclone WebDAV

rclone 默认将 `/media` 对外暴露，开算即用。

```yaml
environment:
  - RCLONE_WEBDAV_USER=myuser
  - RCLONE_WEBDAV_PASS=mypassword
```

WebDAV 客户端连接地址：
```
http://localhost:8080/rclone/
```

### 6. 🔄 Emby 自动扫描

容器内置 `emby-scan-watcher`，利用 `inotifywait` 实时监听 `/media` 目录变化，下载完成后自动通知 Emby 刷新媒体库。

**启用方式：**
1. Emby 后台 → **设置 → 高级 → API 密鑰** 创建一个 API Key
2. 设置环境变量：

```yaml
environment:
  - EMBY_API_KEY=your_api_key_here
```

**工作机制：**
- 后台持续监听，最后一次文件写入后 **30 秒无新事件**才触发，避免下载过程中频繁触发
- `EMBY_API_KEY` 为空时静默跳过，不影响其他服务

### 7. 🔌  MetaTube Server 刷削元数据服务器

容器内置 `MetaTube Server`，刷削元数据服务器。
服务器连接地址：
```
http://localhost:8083
```

### 8. 🛠️ 诊断面板

诊断面板通过 Caddy **Basic Auth** 保护：

```yaml
environment:
  - DEBUG_AUTH_PASS=your_password  # 用户名固定为: `admin`
```

访问 `/debug/` 查看 STRM 同步状态与日志。

## 安全说明

> ⚠️ 容器启动时会检测以下安全风险并打印警告：

| 风险项 | 建议 |
|------|------|
| `ALIST_ADMIN_PASS` 为默认密码 | 请修改为强密码 |
| `RCLONE_WEBDAV_PASS` 未设置 | WebDAV 允许匿名访问，公网环境建议设置 |
| `METUBE_AUTH_PASS` 未设置 | 容器拒绝启动 |
| `DEBUG_AUTH_PASS` 未设置 | 容器拒绝启动 |
| 无 HTTPS | 如有域名，将 `Caddyfile` 中 `:8080` 改为实际域名即自动开启 HTTPS |

> MeTube 和 诊断面板的 Basic Auth 密码支持明文输入，容器内部自动转换为 bcrypt 哈希，用户名固定为 `admin`。

## 环境变量

所有 MeTube、Alist、Emby 原项目的官方环境变量均可直接传入。

### 容器专用变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ALIST_ADMIN_PASS` | _(空)_ | Alist 管理员密码（每次启动时设置） |
| `ALIST_DATA` | `/config/alist` | Alist 数据目录 |
| `EMBY_PROGRAMDATA` | `/config/emby` | Emby 数据目录 |
| `EMBY_API_KEY` | _(空)_ | Emby API 密鑰，用于自动触发媒体库扫描 |
| `METUBE_AUTH_PASS` | _(必填)_ | MeTube Basic Auth 明文密码 |
| `DEBUG_AUTH_PASS` | _(必填)_ | 诊断面板 Basic Auth 明文密码 |
| `METATUBE_SERVER_TOKEN` | _(空)_ | MetaTube Server 访问 Token |
| `RCLONE_WEBDAV_REMOTE` | `/media` | WebDAV 服务的本地目录路径 |
| `RCLONE_WEBDAV_PORT` | `8085` | rclone WebDAV 内部监听端口 |
| `RCLONE_WEBDAV_USER` | _(空)_ | WebDAV 认证用户名 |
| `RCLONE_WEBDAV_PASS` | _(空)_ | WebDAV 认证密码 |

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
| [MetaTube Server](https://github.com/metatube-community/metatube-server) | 刷削元数据服务器 |
| [rclone](https://rclone.org/) | WebDAV 文件服务端 |
| [Caddy](https://caddyserver.com/) | 反向代理 + Basic Auth |
| [Supervisord](http://supervisord.org/) | 进程管理 |
| [inotify-tools](https://github.com/inotify-tools/inotify-tools) | 文件系统实时监听 |

## License

MIT
