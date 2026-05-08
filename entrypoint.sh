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
# Configure qBittorrent
# ------------------------------------------
QBIT_CONFIG_DIR="/config/qBittorrent/qBittorrent"
mkdir -p "$QBIT_CONFIG_DIR"
QBIT_CONF="$QBIT_CONFIG_DIR/qBittorrent.conf"

if [ ! -f "$QBIT_CONF" ]; then
    echo "Initializing qBittorrent default configuration..."
    cat > "$QBIT_CONF" << EOF
[LegalNotice]
Accepted=true

[Preferences]
Downloads\SavePath=/downloads/
WebUI\Port=8082
WebUI\HostHeaderValidation=false
WebUI\CSRFProtection=false
WebUI\LocalHostAuth=false
EOF
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
