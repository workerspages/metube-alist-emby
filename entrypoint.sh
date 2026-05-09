#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

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

# Use env vars with defaults
ALIST_DATA="${ALIST_DATA:-/config/alist}"

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
    # Ensure correct permissions if needed, though running as root it's fine
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
        # 每次启动都更新插件（确保版本最新）
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
