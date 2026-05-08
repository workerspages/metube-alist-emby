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
