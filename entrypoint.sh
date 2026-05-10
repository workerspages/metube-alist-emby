#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Use env vars with defaults
ALIST_DATA="${ALIST_DATA:-/config/alist}"

# ------------------------------------------
# 安全检查：文警默认密码
# ------------------------------------------
if [ "${ALIST_ADMIN_PASS}" = "adminadmin" ] || [ -z "${ALIST_ADMIN_PASS}" ]; then
    echo "[WARN] ⚠️  ALIST_ADMIN_PASS 使用的是默认密码，生产环境请修改！"
fi
if [ "${RCLONE_WEBDAV_PASS}" = "adminadmin" ] || [ -z "${RCLONE_WEBDAV_PASS}" ]; then
    echo "[WARN] ⚠️  RCLONE_WEBDAV_PASS 未设置或使用默认密码， WebDAV 将允许匿名访问！"
fi

# Create necessary directories
mkdir -p /media/metube /media/qbittorrent /media/alist \
    "${ALIST_DATA}" \
    "${EMBY_PROGRAMDATA:-/config/emby}"

# Ensure media directories are accessible
chmod 755 /media /media/metube /media/qbittorrent /media/alist

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
    /usr/local/bin/alist admin set "${ALIST_ADMIN_PASS}" --data "$ALIST_DATA" 2>/dev/null || true
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
QBIT_CONFIG_DIR="/config/qBittorrent/qBittorrent/config"
mkdir -p "$QBIT_CONFIG_DIR"

if [ -d /opt/default-qbittorrent-config ]; then
    echo "Initializing qBittorrent configuration from preset defaults..."
    cp -rn /opt/default-qbittorrent-config/* "$QBIT_CONFIG_DIR/" 2>/dev/null || true
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
