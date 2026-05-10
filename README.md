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
| `/rclone/` | rclone WebDAV | WebDAV 文件服务 |
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
| `/media/alist` | Alist 网盘通过 rclone 挂载，作为 Emby 媒体源 |
| `/media/metube` | Metube 下载的数据，作为 Emby 媒体源 |
| `/media/qbittorrent` | qBittorrent 下载的数据，作为 Emby 媒体源 |
| `/config` | 所有服务配置数据 |
| `/config/rclone` | rclone 配置文件目录（`rclone.conf`）|

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
# PaaS 只挂载一个持久卷到 /data
# 将 /media 和 /config 软链接到 /data 下的子目录
DATA_ROOT="${PERSISTENT_ROOT:-/data}"

mkdir -p "${DATA_ROOT}/media" "${DATA_ROOT}/config"

# 如果 /media 不是软链接，则替换为软链接
if [ ! -L /media ]; then
    rm -rf /media
    ln -s "${DATA_ROOT}/media" /media
fi

# 如果 /config 不是软链接，则替换为软链接
if [ ! -L /config ]; then
    rm -rf /config
    ln -s "${DATA_ROOT}/config" /config
fi
# ==== 结束 ====

# 原有逻辑继续...
```

PaaS 平台只需挂载 **一个持久卷到 `/data`**，`/data/media` 和 `/data/config` 自动对应原来的两个目录。

#### 方案二：修改 Dockerfile，构建时预置软链接

如果不方便修改运行时脚本，可在 [Dockerfile](/Dockerfile) 中添加：

```dockerfile
# 预置软链接（构建时）
RUN mkdir -p /data/media /data/config \
    && ln -sf /data/media /media \
    && ln -sf /data/config /config
```

然后 PaaS 平台仅挂载持久卷到 `/data`。

#### PaaS 配置对照

| 原 docker-compose 挂载 | PaaS 单卷方案 |
|---|---|
| `./media:/media` | 持久卷 → `/data`，软链 `/media` → `/data/media` |
| `./config:/config` | 持久卷 → `/data`，软链 `/config` → `/data/config` |

#### 注意事项

- **首次启动前**确保持久卷是空的，避免软链接被已有目录覆盖
- 项目的 `entrypoint.sh` 中已有 `mkdir -p /media/... /config/...` 的逻辑，软链接初始化代码必须放在这些 `mkdir` 语句**之前**，否则会因目录已存在导致软链接失败
- 环境变量 `ALIST_DATA` 默认指向 `/config/alist`，软链接生效后路径自动正确，无需额外改动


</details>

---


## 初始配置

### 1. ☁️ 配置 Alist

通过环境变量 `ALIST_ADMIN_PASS` 设置管理员密码（适配 PaaS 无终端环境）：

```bash
docker run -d --name media-center --privileged \
  -p 8080:8080 \
  -e ALIST_ADMIN_PASS=your_password \
  -e ALIST_USER=admin \
  -e ALIST_PASS=your_password \
  -v ./media:/media \
  -v ./config:/config \
  ghcr.io/workerspages/metube-alist-emby:latest
```

> `ALIST_ADMIN_PASS` — Alist 管理员登录密码
> `ALIST_USER` / `ALIST_PASS` — rclone WebDAV 挂载认证（通常与管理员相同）

访问 `/alist/` 登录，在**存储**页面添加网盘驱动。

#### 默认登录信息：
> 用户名：`admin`
> 密码：`adminadmin`


### 2. 📺 配置 Emby

访问 `/web/` 完成设置向导，添加媒体库选择：
- `/media/alist` — Alist 挂载的网盘文件
- `/media/metube` — MeTube 下载的视频
- `/media/qbittorrent` — qBittorrent 下载的视频

注意：
纯手动输入（不要在下面的列表中找目录，找不到的）
直接点击输入框。
准确输入对应的文件夹路径，例如 `/media/metube`。
重要：输入完毕后，仔细检查光标位置，确保结尾绝对没有哪怕一个空格！
点击输入框右侧的放大镜（搜索）图标，或者直接点击下方的绿色"确定"按钮。

插件目录：
`/opt/emby-server/system/plugins/`

### Emby 客户端在连接方法：
Emby 客户端在连接时，只需要服务器的**基础域名（Base URL）**。末尾的 `/web/` 是你在浏览器中访问网页端时使用的路径，客户端**不需要且不能**带上它，否则会导致 API 路径识别错误。
1. 点击弹窗上的**"明白"**。
2. 将**"主机"**一栏修改为（删掉后面的 `/web/`，并且确保末尾没有斜杠）：
   > `https://metube-alist-emby.up.railway.app`
3. **"端口"**一栏：因为你使用的是 `https` 开头的地址，端口通常可以**留空**（它会自动识别为 443），或者手动填入 `443`。


#### 默认登录信息：
> 用户名：`root`
> 密码：`空`

### 3. ⬇️ 配置 MeTube

访问 `/metube/`，粘贴链接下载视频，自动出现在 Emby 媒体库。

#### 默认登录信息：
> 用户名：`空`
> 密码：`空`

### 4. 🧲 配置 qBittorrent

访问 `/qbittorrent/`，粘贴链接下载视频，自动出现在 Emby 媒体库。

#### 默认登录信息：
> 用户名：`admin`
> 密码：`admin`

### 5. 📂 配置 rclone WebDAV

容器内置 rclone，启动时自动以 WebDAV 模式对外提供文件服务，通过 `/rclone/` 路径访问。

#### 默认行为

默认将容器内 `/media` 目录作为 WebDAV 根目录，**无需任何配置**即可访问：

```
http://localhost:8080/rclone/
```

#### 挂载云盘 Remote

如需将 rclone 云盘（如 Google Drive、OneDrive）作为 WebDAV 服务，需提前准备好 `rclone.conf`：

```bash
docker run -d --name media-center \
  -p 8080:8080 \
  -e RCLONE_WEBDAV_REMOTE="gdrive:/Movies" \
  -e RCLONE_WEBDAV_USER=myuser \
  -e RCLONE_WEBDAV_PASS=mypassword \
  -v ./media:/media \
  -v ./config:/config \
  -v ./rclone.conf:/config/rclone/rclone.conf \
  ghcr.io/workerspages/metube-alist-emby:latest
```

#### WebDAV 客户端连接

| 客户端 | 地址示例 |
|--------|---------|
| 浏览器 | `http://localhost:8080/rclone/` |
| macOS Finder | `http://localhost:8080/rclone/` |
| Windows 网络驱动器 | `http://localhost:8080/rclone/` |
| Infuse / nPlayer | `http://localhost:8080/rclone/` |


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
| `METATUBE_SERVER_TOKEN` | _(空)_ | MetaTube Server 访问 Token |
| `RCLONE_WEBDAV_REMOTE` | `/media` | rclone WebDAV 服务的源路径或 remote，如 `gdrive:/Movies` |
| `RCLONE_WEBDAV_PORT` | `8085` | rclone WebDAV 内部监听端口（Caddy 转发用） |
| `RCLONE_WEBDAV_USER` | _(空)_ | WebDAV 认证用户名，空则不启用鉴权 |
| `RCLONE_WEBDAV_PASS` | _(空)_ | WebDAV 认证密码，空则不启用鉴权 |
| `RCLONE_CONFIG` | `/config/rclone/rclone.conf` | rclone 配置文件路径（持久化到 `/config` 卷）|


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
| [rclone](https://rclone.org/) | WebDAV 文件服务 / 云盘挂载 |
| [Caddy](https://caddyserver.com/) | 反向代理 |
| [Supervisord](http://supervisord.org/) | 进程管理 |

## License

MIT
