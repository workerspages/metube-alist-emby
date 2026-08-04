#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Use env vars with defaults
ALIST_DATA="${ALIST_DATA:-/app/data/alist}"

# ------------------------------------------
# 检测 Alist 挂载模式（mount / strm）
# mount: 通过 rclone FUSE 挂载，Emby 原生读取视频
# strm:  生成 .strm 文件，ffmpeg 自动截取视频封面
# ------------------------------------------
ALIST_MOUNT_MODE="${ALIST_MOUNT_MODE:-auto}"
if [ "$ALIST_MOUNT_MODE" = "auto" ]; then
    if [ -c /dev/fuse ]; then
        export ALIST_MOUNT_MODE="mount"
        echo "[INFO] ✅ FUSE 可用，使用 rclone mount 模式（Emby 原生读取视频文件）"
    else
        export ALIST_MOUNT_MODE="strm"
        echo "[INFO] 📝 FUSE 不可用，使用 STRM 同步模式（ffmpeg 自动截取视频封面）"
    fi
else
    export ALIST_MOUNT_MODE
    echo "[INFO] 挂载模式已手动指定: ALIST_MOUNT_MODE=$ALIST_MOUNT_MODE"
fi

# ------------------------------------------
# 安全检查：告警默认密码
# ------------------------------------------
if [ "${ALIST_ADMIN_PASS}" = "adminadmin" ] || [ -z "${ALIST_ADMIN_PASS}" ]; then
    echo "[WARN] ⚠️  ALIST_ADMIN_PASS 使用的是默认密码，生产环境请修改！"
fi
if [ "${RCLONE_WEBDAV_PASS}" = "adminadmin" ] || [ -z "${RCLONE_WEBDAV_PASS}" ]; then
    echo "[WARN] ⚠️  RCLONE_WEBDAV_PASS 未设置或使用默认密码，WebDAV 将允许匿名访问！"
fi

# ------------------------------------------
# 生成 MeTube 和 诊断面板的 bcrypt 哈希
# 支持传入明文密码，自动转换，跟WebDAV一致
# ------------------------------------------
if [ -n "${METUBE_AUTH_PASS}" ]; then
    export METUBE_AUTH_HASH=$(caddy hash-password --plaintext "${METUBE_AUTH_PASS}")
    echo "[INFO] MeTube Basic Auth 已启用（用户名: admin）"
elif [ -z "${METUBE_AUTH_HASH}" ]; then
    echo "[WARN] ⚠️  METUBE_AUTH_PASS 未设置，MeTube 将无法启动（Caddy basic_auth 需要 METUBE_AUTH_HASH）"
    echo "[WARN]    请设置环境变量 METUBE_AUTH_PASS='你的密码'"
    exit 1
fi

if [ -n "${DEBUG_AUTH_PASS}" ]; then
    export DEBUG_AUTH_HASH=$(caddy hash-password --plaintext "${DEBUG_AUTH_PASS}")
    echo "[INFO] 诊断面板 Basic Auth 已启用（用户名: admin）"
elif [ -z "${DEBUG_AUTH_HASH}" ]; then
    echo "[WARN] ⚠️  DEBUG_AUTH_PASS 未设置，诊断面板将无法启动（Caddy basic_auth 需要 DEBUG_AUTH_HASH）"
    echo "[WARN]    请设置环境变量 DEBUG_AUTH_PASS='你的密码'"
    exit 1
fi

# Create necessary directories
mkdir -p /media/metube /media/qbittorrent /media/movies /media/alist \
    "${ALIST_DATA}" \
    "${EMBY_PROGRAMDATA:-/app/data/emby}" \
    /app/data/qBittorrent/qBittorrent/config

# ------------------------------------------
# WebDAV Backup Pull (For Ephemeral PaaS)
# ------------------------------------------
if [ -n "${WEBDAV_BACKUP_URL}" ]; then
    echo "[INFO] WEBDAV_BACKUP_URL is set. Preparing to pull backup from WebDAV..."
    
    # Generate rclone config
    cat <<EOF > /tmp/rclone-backup.conf
[backup]
type = webdav
url = ${WEBDAV_BACKUP_URL}
vendor = other
user = ${WEBDAV_BACKUP_USER}
pass = $(rclone obscure "${WEBDAV_BACKUP_PASS}" 2>/dev/null || echo "")
EOF

    echo "[INFO] Pulling /config data from WebDAV..."
    # Copy from WebDAV to /config. We ignore errors so container can start even if first pull fails
    rclone copy --config /tmp/rclone-backup.conf backup: /config/ || echo "[WARN] WebDAV pull failed or bucket is empty. Starting fresh."
    echo "[INFO] WebDAV pull complete."
fi

# ------------------------------------------
# Initial DB Restore (PaaS SQLite Protection)
# ------------------------------------------
if [ -x /app/db-sync.sh ]; then
    /app/db-sync.sh restore
fi

# ------------------------------------------
# Auto-recover corrupted SQLite databases for Emby
# ------------------------------------------
if command -v sqlite3 >/dev/null 2>&1; then
    echo "[INFO] Checking Emby SQLite databases for corruption..."
    for db in "${EMBY_PROGRAMDATA:-/app/data/emby}/data"/*.db; do
        if [ -f "$db" ]; then
            # Use quick_check to avoid extremely long startup times on large libraries
            if ! sqlite3 "$db" "PRAGMA quick_check;" | grep -qi "^ok$"; then
                echo "[WARN] ⚠️  Corruption detected in $db! Attempting recovery..."
                # .recover extracts SQL and we pipe it to a new db
                if sqlite3 "$db" ".recover" | sqlite3 "$db.recovered"; then
                    mv "$db" "$db.corrupted.bak"
                    mv "$db.recovered" "$db"
                    echo "[INFO] ✅  Successfully recovered $db."
                else
                    echo "[ERROR] ❌  Failed to recover $db."
                    rm -f "$db.recovered"
                fi
            fi
        fi
    done
fi

# Ensure media directories are accessible
chmod 755 /media /media/metube /media/qbittorrent /media/movies /media/alist

# ------------------------------------------
# Initialize Emby configuration
# ------------------------------------------
if [ -d /opt/default-emby-config ]; then
    echo "Initializing Emby configuration from defaults..."
    cp -rn /opt/default-emby-config/* "${EMBY_PROGRAMDATA:-/config/emby}/" 2>/dev/null || true
fi

# ------------------------------------------
# Install Emby plugins from /opt/emby-plugins
# Emby system plugins directory: /opt/emby-server/system/plugins/
# ------------------------------------------
EMBY_PLUGIN_DIR="/opt/emby-server/system/plugins"
if [ -d /opt/emby-plugins ]; then
    for dll in /opt/emby-plugins/*.dll; do
        [ -f "$dll" ] || continue
        PLUGIN_NAME=$(basename "$dll")
        cp "$dll" "$EMBY_PLUGIN_DIR/"
        echo "Installed Emby plugin: $PLUGIN_NAME -> $EMBY_PLUGIN_DIR/"
    done
fi

# ------------------------------------------
# Initialize Alist configuration
# ------------------------------------------
if [ -d /opt/default-alist-config ]; then
    echo "Initializing Alist configuration from defaults..."
    cp -rn /opt/default-alist-config/* "${ALIST_DATA}/" 2>/dev/null || true
fi

# ------------------------------------------
# Configure Alist
# ------------------------------------------
ALIST_CONFIG="${ALIST_DATA}/config.json"

# First run: generate default config
if [ ! -f "$ALIST_CONFIG" ]; then
    echo "First run: initializing Alist..."
    cd "$ALIST_DATA" && /usr/local/bin/alist admin random --data "$ALIST_DATA" 2>/dev/null || true
fi

# Set admin password via environment variable (for PaaS without terminal)
if [ -n "${ALIST_ADMIN_PASS}" ]; then
    echo "Setting Alist admin password from environment variable..."
    /usr/local/bin/alist admin set "${ALIST_ADMIN_PASS}" --data "$ALIST_DATA" || echo "[WARN] Failed to set Alist admin password."
fi

# Set Alist site_url for subpath routing
if [ -f "$ALIST_CONFIG" ] && command -v jq &> /dev/null; then
    jq '.site_url = "/alist"' "$ALIST_CONFIG" > /tmp/alist_config.json \
        && mv /tmp/alist_config.json "$ALIST_CONFIG"
    echo "Alist site_url set to /alist"
fi

# ------------------------------------------
# Initialize qBittorrent configuration
# ------------------------------------------
QBIT_CONFIG_DIR="/app/data/qBittorrent/qBittorrent/config"
mkdir -p "$QBIT_CONFIG_DIR"

if [ -d /opt/default-qbittorrent-config ]; then
    echo "Initializing qBittorrent configuration from preset defaults..."
    cp -rn /opt/default-qbittorrent-config/* "$QBIT_CONFIG_DIR/" 2>/dev/null || true
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
