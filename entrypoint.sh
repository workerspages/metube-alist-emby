#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Use env vars with defaults
ALIST_DATA="${ALIST_DATA:-/config/alist}"

# Create necessary directories
mkdir -p /downloads /media/alist \
    "${ALIST_DATA}" \
    "${EMBY_PROGRAMDATA:-/config/emby}"

# Ensure media directories are accessible
chmod 755 /downloads /media /media/alist

# Symlink downloads into /media so Emby's file browser can find it
# Emby only shows standard paths like /media in its directory picker
ln -sfn /downloads /media/downloads

# ------------------------------------------
# Install Emby plugins from /opt/emby-plugins
# Emby loads .dll files directly from: plugins/
# ------------------------------------------
EMBY_PLUGIN_DIR="${EMBY_PROGRAMDATA:-/config/emby}/plugins"
mkdir -p "$EMBY_PLUGIN_DIR"
if [ -d /opt/emby-plugins ]; then
    for dll in /opt/emby-plugins/*.dll; do
        [ -f "$dll" ] || continue
        PLUGIN_NAME=$(basename "$dll")
        PLUGIN_BASE=$(basename "$dll" .dll)
        # 清理旧版错误安装的子目录格式
        if [ -d "$EMBY_PLUGIN_DIR/${PLUGIN_BASE}_1.0.0.0" ]; then
            rm -rf "$EMBY_PLUGIN_DIR/${PLUGIN_BASE}_1.0.0.0"
            echo "Cleaned up old plugin dir: ${PLUGIN_BASE}_1.0.0.0"
        fi
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

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
