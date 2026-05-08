#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Create necessary directories
mkdir -p /downloads /config/alist /config/emby

# ------------------------------------------
# Configure Alist
# ------------------------------------------
ALIST_CONFIG="/config/alist/config.json"
if [ ! -f "$ALIST_CONFIG" ]; then
    echo "Generating Alist default config..."
    cd /config/alist && /usr/local/bin/alist admin random --data /config/alist 2>/dev/null || true
fi

# Set Alist site_url for subpath routing
if [ -f "$ALIST_CONFIG" ] && command -v jq &> /dev/null; then
    jq '.site_url = "/alist"' "$ALIST_CONFIG" > /tmp/alist_config.json \
        && mv /tmp/alist_config.json "$ALIST_CONFIG"
    echo "Alist site_url set to /alist"
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
