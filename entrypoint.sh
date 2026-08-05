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
if [ "${WEBDAV_SYNC_ENABLE}" = "true" ]; then
    echo "[INFO] WEBDAV_SYNC_ENABLE is true. Preparing to pull backup from WebDAV..."
    
    # Generate rclone config
    cat <<EOF > /tmp/rclone-backup.conf
[backup]
type = webdav
url = ${WEBDAV_BACKUP_URL}
vendor = other
user = ${WEBDAV_BACKUP_USER}
pass = $(rclone obscure "${WEBDAV_BACKUP_PASS}" 2>/dev/null || echo "")
EOF

    echo "[INFO] Validating WebDAV connection..."
    (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone mkdir --config /tmp/rclone-backup.conf backup:config/ > /tmp/rclone-validation.log 2>&1)
    RET1=$?
    (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone mkdir --config /tmp/rclone-backup.conf backup:media/ >> /tmp/rclone-validation.log 2>&1)
    RET2=$?
    
    if [ $RET1 -ne 0 ] || [ $RET2 -ne 0 ]; then
        echo "================================================================="
        echo "[ERROR] ❌ WebDAV connection validation failed!"
        echo "[ERROR] Please check WEBDAV_BACKUP_URL, WEBDAV_BACKUP_USER, and WEBDAV_BACKUP_PASS."
        echo "[ERROR] Detailed rclone error:"
        cat /tmp/rclone-validation.log
        echo "================================================================="
        echo "[ERROR] 🛑 Container startup aborted due to invalid WebDAV configuration."
        exit 1
    fi
    echo "[INFO] ✅ WebDAV connection successful!"

    echo "[INFO] Pulling /config data from WebDAV..."
    (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone copy --config /tmp/rclone-backup.conf backup:config/ /config/ || echo "[WARN] WebDAV pull for /config failed or bucket is empty.")
    echo "[INFO] Pulling /media data from WebDAV..."
    (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone copy --config /tmp/rclone-backup.conf backup:media/ /media/ || echo "[WARN] WebDAV pull for /media failed or bucket is empty.")
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
    
    # Check if the destination is an uncompleted wizard state (e.g. cached by db-sync.sh from a previous failed run)
    if [ -f "${EMBY_PROGRAMDATA:-/app/data/emby}/config/system.xml" ] && grep -q "<IsStartupWizardCompleted>false</IsStartupWizardCompleted>" "${EMBY_PROGRAMDATA:-/app/data/emby}/config/system.xml" 2>/dev/null; then
        echo "[INFO] Detected uncompleted wizard state. Forcefully applying preset..."
        # CRITICAL: We MUST delete any existing SQLite -wal and -shm files!
        # Otherwise, if 4.9.x corrupted the db or the state is incomplete, the leftover WAL file 
        # will instantly overwrite and destroy the freshly copied preset users.db!
        rm -f "${EMBY_PROGRAMDATA:-/app/data/emby}/data/"*.db-wal 2>/dev/null || true
        rm -f "${EMBY_PROGRAMDATA:-/app/data/emby}/data/"*.db-shm 2>/dev/null || true
        cp -ra /opt/default-emby-config/* "${EMBY_PROGRAMDATA:-/app/data/emby}/" 2>/dev/null || true
    else
        # Normal safe copy that won't overwrite existing configured data
        cp -rn /opt/default-emby-config/* "${EMBY_PROGRAMDATA:-/app/data/emby}/" 2>/dev/null || true
    fi


fi

# ------------------------------------------
# Install Emby plugins from /opt/emby-plugins
# Emby data plugins directory: ${EMBY_PROGRAMDATA}/plugins/
# ------------------------------------------
EMBY_PLUGIN_DIR="${EMBY_PROGRAMDATA:-/app/data/emby}/plugins"
mkdir -p "$EMBY_PLUGIN_DIR"
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

# ------------------------------------------
# Apply ENABLED_SERVICES if specified
# ------------------------------------------
if [ -n "$ENABLED_SERVICES" ] || [ -n "$DISABLED_SERVICES" ]; then
    echo "[INFO] Custom service selection is set. Applying..."
    python3 -c "
import os

enabled_env = os.environ.get('ENABLED_SERVICES', '').strip()
disabled_env = os.environ.get('DISABLED_SERVICES', '').strip()

enabled_services = [s.strip() for s in enabled_env.split(',') if s.strip()]
disabled_services = [s.strip() for s in disabled_env.split(',') if s.strip()]

if enabled_services or disabled_services:
    lines = []
    current_prog = None
    with open('/etc/supervisor/conf.d/supervisord.conf', 'r') as f:
        for line in f:
            if line.startswith('[program:'):
                current_prog = line.strip()[9:-1]
                
            is_enabled = True
            if enabled_services and current_prog not in enabled_services:
                is_enabled = False
            if disabled_services and current_prog in disabled_services:
                is_enabled = False
                
            if line.startswith('autostart=') and current_prog and not is_enabled:
                lines.append('autostart=false\n')
            else:
                lines.append(line)
                
    with open('/etc/supervisor/conf.d/supervisord.conf', 'w') as f:
        f.writelines(lines)
    print(f'[INFO] Service selection applied. Enabled list: {enabled_services}, Disabled list: {disabled_services}')
"
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
