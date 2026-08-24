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
- 带换行符的格式（适合阅读和修改参数）
> 如果你需要在终端里修改密码或 API Key，这种带 \ 换行的格式会更清晰（直接整体复制粘贴到 Linux/macOS 终端即可执行）:
```bash
docker run -d \
  --name media-center \
  --restart unless-stopped \
  -p 8080:8080 \
  -v ./media:/media \
  -v ./config:/config \
  -e TZ=Asia/Shanghai \
  -e ALIST_USER=admin \
  -e ALIST_ADMIN_PASS=adminadmin \
  -e RCLONE_WEBDAV_REMOTE=/media \
  -e RCLONE_WEBDAV_PORT=8085 \
  -e RCLONE_WEBDAV_USER=admin \
  -e RCLONE_WEBDAV_PASS=adminadmin \
  -e EMBY_API_KEY= \
  --health-cmd "curl -f http://localhost:8080/" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-retries 3 \
  --health-start-period 60s \
  ghcr.io/workerspages/metube-alist-emby:latest
```
- 纯单行版本（单排格式）
> 为了方便直接复制使用，这里提供纯单行版本（单排格式），并且默认添加了 -d 参数让其在后台运行：
```
docker run -d --name media-center --restart unless-stopped -p 8080:8080 -v ./media:/media -v ./config:/config -e TZ=Asia/Shanghai -e ALIST_USER=admin -e ALIST_ADMIN_PASS=adminadmin -e RCLONE_WEBDAV_REMOTE=/media -e RCLONE_WEBDAV_PORT=8085 -e RCLONE_WEBDAV_USER=admin -e RCLONE_WEBDAV_PASS=adminadmin -e EMBY_API_KEY= --health-cmd "curl -f http://localhost:8080/" --health-interval 30s --health-timeout 10s --health-retries 3 --health-start-period 60s ghcr.io/workerspages/metube-alist-emby:latest
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

### ☁️ WebDAV 远程自动备份 (适用于无持久化 PaaS)

如果您部署在完全没有任何持久化存储的 PaaS 平台（重启会清空所有数据），可以配置以下环境变量，容器会在每次启动时自动从 WebDAV 拉取历史数据，并在运行期间自动将**所有配置数据（/config）和所有媒体下载数据（/media）**增量备份回网盘。完美解决 PaaS 数据丢失问题。

> [!WARNING]
> 因为包含了 `/media`（视频大文件），请确保 PaaS 与云盘之间有充足的带宽与流量配额。在本地 VPS 有持久卷的环境中，请**不要**开启此功能。

| 环境变量 | 说明 |
|---------|------|
| `WEBDAV_SYNC_ENABLE` | **总开关**，必须设置为 `true` 才会开启 WebDAV 备份功能 |
| `WEBDAV_BACKUP_URL` | 外部 WebDAV 网盘的完整 URL，如 `https://dav.jianguoyun.com/dav/backup/` |
| `WEBDAV_BACKUP_USER` | WebDAV 用户名 |
| `WEBDAV_BACKUP_PASS` | WebDAV 密码 |
| `WEBDAV_SYNC_INTERVAL` | 自动备份的时间间隔（秒），默认 `300` |

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

> 默认登录：用户名: `admin` 密码: 通过环境变量 `ALIST_ADMIN_PASS` 设置（docker-compose.yml 中默认为 `adminadmin`，**请务必修改**）

### 2. 📺 配置 Emby

访问 `/web/` 完成设置向导，添加媒体库选择：
- `/media/alist` — Alist 挂载的网盘文件
- `/media/metube` — MeTube 下载的视频
- `/media/qbittorrent` — qBittorrent 下载的视频

> 注意：纯手动输入路径，不要在列表中搜索。确保结尾没有多余空格。

- 插件目录：`/opt/emby-server/system/plugins/`
- Emby 的安装目录：`/opt/emby-server`

**内置插件：**
| 插件 | 用途 |
|------|------|
| [MetaTube](https://github.com/metatube-community/metatube-sdk-go) | 刷削元数据 |

> `.strm` 模式下的视频封面由容器内置的 **ffmpeg 截图服务**自动生成，无需任何 Emby 插件，不受 Emby 版本限制。

#### 🔀 Alist 挂载模式（自动切换）

容器支持两种模式访问 Alist 网盘文件，**启动时自动检测**：

| 模式 | 触发条件 | 原理 | 视频封面 | 适用场景 |
|------|---------|------|---------|---------|
| **mount** | `/dev/fuse` 存在 | rclone FUSE 挂载 Alist WebDAV 到 `/media/alist` | ✅ Emby 原生 Image Capture | 本地 Docker / VPS |
| **strm** | 无 FUSE 支持 | 生成 `.strm` 文件 + ffmpeg 自动截图 | ✅ ffmpeg 截取画面（无插件依赖） | PaaS 平台 |

通过环境变量 `ALIST_MOUNT_MODE` 可手动覆盖：`auto`（默认）/ `mount` / `strm`

> **本地 Docker 用户**：docker-compose.yml 中已配置 `devices: [/dev/fuse]`，开箱即用。
> **PaaS 用户**：无需配置，自动回退到 strm 模式。

> `https://your-domain.com`

> 默认登录：用户名: `admin` 密码:`adminadmin`

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

### 9. 🎛️ 按需启动特定服务 (ENABLED_SERVICES / DISABLED_SERVICES)

我们提供两种模式（白名单与黑名单）来按需启动特定服务。这对于仅需启动代理/下载节点而不启动 Emby 等重负载应用非常有用。

**支持的服务名称**（对应核心组件）：
`caddy`, `emby`, `metube`, `alist`, `alist-mount`, `alist-strm-sync`, `strm-thumb-gen`, `strm-debug`, `qbittorrent`, `metatube-server`, `rclone-webdav`, `emby-scan-watcher`, `db-sync`

#### 模式 A: 黑名单排除（推荐，更简单）
如果您想启动绝大多数服务，仅仅不想启动其中一两个，请使用 `DISABLED_SERVICES`：
```yaml
    environment:
      # 不启动 qBittorrent 和其关联服务，其他一切照常启动
      - DISABLED_SERVICES=qbittorrent
```

#### 模式 B: 白名单指定
如果您只需要极少数的服务，请使用 `ENABLED_SERVICES`（逗号分隔）：
```yaml
    environment:
      # 仅启动代理、Alist和MeTube
      - ENABLED_SERVICES=caddy,alist,metube
```

> [!TIP]
> 留空或不配置这两个变量时，容器将默认启动**所有**内置服务。被排除的服务将被禁止自启（状态为 `STOPPED`），但您仍可以通过诊断面板随时手动拉起它们。黑名单的优先级高于白名单。

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
| `ENABLED_SERVICES` | _(空)_ | 按需启动的服务列表（白名单，逗号分隔），为空则全部启动 |
| `DISABLED_SERVICES`| _(空)_ | 按需禁用的服务列表（黑名单，逗号分隔），为空则不禁用任何服务 |
| `ALIST_ADMIN_PASS` | _(空)_ | Alist 管理员密码（每次启动时设置） |
| `ALIST_DATA` | `/app/data/alist` | Alist 运行时数据目录（通过 db-sync 与 `/config/alist` 自动双向同步） |
| `EMBY_PROGRAMDATA` | `/app/data/emby` | Emby 运行时数据目录（通过 db-sync 与 `/config/emby` 自动双向同步） |
| `EMBY_API_KEY` | _(空)_ | Emby API 密鑰，用于自动触发媒体库扫描 |
| `METUBE_AUTH_PASS` | _(必填)_ | MeTube Basic Auth 明文密码 |
| `DEBUG_AUTH_PASS` | _(必填)_ | 诊断面板 Basic Auth 明文密码 |
| `METATUBE_SERVER_TOKEN` | _(空)_ | MetaTube Server 访问 Token |
| `RCLONE_WEBDAV_REMOTE` | `/media` | WebDAV 服务的本地目录路径 |
| `RCLONE_WEBDAV_PORT` | `8085` | rclone WebDAV 内部监听端口 |
| `RCLONE_WEBDAV_USER` | _(空)_ | WebDAV 认证用户名 |
| `RCLONE_WEBDAV_PASS` | _(空)_ | WebDAV 认证密码 |
| `WEBDAV_SYNC_ENABLE` | _(空)_ | WebDAV 远程备份总开关，设为 `true` 开启 |
| `WEBDAV_BACKUP_URL` | _(空)_ | 用于远程备份和还原的 WebDAV 地址 |
| `WEBDAV_BACKUP_USER` | _(空)_ | 用于远程备份的 WebDAV 用户名 |
| `WEBDAV_BACKUP_PASS` | _(空)_ | 用于远程备份的 WebDAV 密码 |
| `WEBDAV_SYNC_INTERVAL`| `300` | WebDAV 远程备份间隔（秒） |
| `RESET_ALIST_DB` | _(空)_ | **物理核弹开关**：设为 `true` 并在重启容器时强制清空并重建损坏的 Alist 数据库（修复无尽崩溃）。修复后请务必移除此变量或设为 ` false`。 |

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

## 内部服务进程解析

为了让各个组件完美配合并在无状态云平台等环境下稳定运行，本项目在容器内部署了多个各司其职的服务。以下是可在诊断面板（Supervisor）中看到的各项后台进程详细说明：

| 服务名称 | 分类 | 核心用途与原理解析 |
| :--- | :--- | :--- |
| `caddy` | 🌐 代理入口 | **Web 反向代理服务器**。整个容器的“大门”，对外只暴露 8080 端口。负责将请求路由分发给具体的后台服务，并为不自带密码系统的服务（如 MeTube）提供拦截保护。 |
| `emby` | 🎬 媒体核心 | **流媒体服务器**。提供海报墙，用于刮削、管理和播放所有的影视资源。 |
| `qbittorrent` | ⬇️ 下载核心 | **BT/PT 下载客户端**。内置 EE 增强版，用于挂机下载种子和磁力资源。 |
| `metube` | ⬇️ 下载核心 | **流媒体视频下载器**。粘贴 YouTube、B站等链接即可一键下载视频。 |
| `alist` | ☁️ 网盘核心 | **网盘聚合管理工具**。将阿里云盘、夸克等市面常见网盘聚合在一起统一管理。 |
| `alist-mount` | 🔌 核心兼容 | **Alist 本地虚拟挂载**。后台利用 rclone 将 Alist 以 FUSE 形式挂载为虚拟本地硬盘，使 Emby 能够像读取本地文件一样读取网盘。 |
| `alist-strm-sync`| 🔌 核心兼容 | **STRM 占位文件同步**。PaaS 环境专属组件。当云平台不支持 FUSE 挂载时，它在本地生成极小的 `.strm` 文本文件假装视频存在，使 Emby 依然能播放网盘内容。 |
| `strm-thumb-gen` | 🔌 核心兼容 | **STRM 网盘自动截图**。因为 Emby 无法直接提取网盘视频封面，它在后台利用 FFmpeg 悄悄提取网盘视频的第一帧画面作为海报墙封面。 |
| `emby-scan-watcher`| 🤖 自动辅助 | **媒体库变动自动触发器**。实时监控下载文件夹，一旦有新文件下载完毕，立刻通知 Emby 刷新媒体库，实现“下载完秒出海报”。 |
| `metatube-server`| 🤖 自动辅助 | **特殊元数据刮削后端**。配合对应插件，专门从网上拉取部分特殊来源视频的简介与封面。 |
| `rclone-webdav` | 🤖 自动辅助 | **WebDAV 文件共享端**。将容器的下载目录对外暴露，方便手机 Infuse 或电脑文件管理器直接远程挂载使用。 |
| `strm-debug` | 🛠️ 运维监控 | **诊断与调试面板**。提供一个 Web 界面，方便随时查看所有底层运行状态与日志。 |
| `db-sync` | 🛠️ 运维监控 | **云端数据备份守护进程**。专为 PaaS 平台设计。若配置了外部备份盘，它会定时将所有服务的配置数据和下载数据增量备份至云端防止丢失。 |

## 常见问题与故障排除 (FAQ & Troubleshooting)

### Q1: 部署到 PaaS 云端后，服务一直无法就绪（被强杀或不断重启），或者在日志看到 Alist 狂刷 `database disk image is malformed`？
**原因分析：** 
Alist 的底层 SQLite 数据库在突然断电、存储空间不足或不稳定的云平台上很容易发生表级别的结构损坏（哪怕物理文件看似完好）。这种“残缺”的库会导致 Alist 在启动极短的时间内（不到1秒）发生严重崩溃，进而在 `supervisord` 守护进程下引发无限重启死循环。这种无间断的报错不仅占用资源，还会导致 CF 等云平台的健康检查（Healthcheck）判定服务未就绪，从而发送 `Exit status 137` 强杀容器。

**解决办法：**
我们内置了一个**“物理核弹”**级别的安全开关来处理这种不死不灭的僵尸库。
1. 去您的云端控制面板的环境变量（Environment Variables）设置中。
2. 添加一个新的环境变量：`RESET_ALIST_DB`，值设置为 `true`。
3. 重启/重新部署容器。
4. 启动时容器会自动备份并物理抹除损坏的数据库文件，让 Alist 重获新生，恢复健康的 `RUNNING` 状态。
5. ⚠️ **切记：修复成功后，务必将 `RESET_ALIST_DB` 环境变量删除或设为 `false`，否则每次重启都会清空您的 Alist 挂载配置！**

## 技术栈

| 组件 | 用途 |
|------|------|
| [Emby](https://emby.media/) | 媒体服务器 |
| [MeTube](https://github.com/alexta69/metube) | yt-dlp Web 下载器 |
| [qBittorrent EE](https://github.com/c0re100/qBittorrent-Enhanced-Edition) | BT/PT 增强版下载客户端 |
| [Alist](https://github.com/AlistGo/alist) | 网盘挂载工具 |
| [MetaTube Server](https://github.com/metatube-community/metatube-server) | 刷削元数据服务器 |
| [ffmpeg](https://ffmpeg.org/) | .strm 模式下自动截取视频画面作为封面（替代 StrmAssistant 插件，无 Emby 版本限制） |
| [rclone](https://rclone.org/) | WebDAV 文件服务端 |
| [Caddy](https://caddyserver.com/) | 反向代理 + Basic Auth |
| [Supervisord](http://supervisord.org/) | 进程管理 |
| [inotify-tools](https://github.com/inotify-tools/inotify-tools) | 文件系统实时监听 |

## License

MIT
