#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Create necessary directories
mkdir -p /downloads /config/alist /config/emby

# ------------------------------------------
# Configure Emby base URL
# Let Emby generate its own config on first run,
# then patch BaseUrl afterwards
# ------------------------------------------
EMBY_SYSTEM_XML="/config/emby/config/system.xml"
if [ ! -f "$EMBY_SYSTEM_XML" ]; then
    echo "First run: starting Emby to generate default config..."
    /opt/emby-server/bin/emby-server -programdata /config/emby &
    EMBY_PID=$!

    # Wait for config file to appear (max 60s)
    for i in $(seq 1 60); do
        if [ -f "$EMBY_SYSTEM_XML" ]; then
            echo "Emby config generated."
            break
        fi
        sleep 1
    done

    # Stop Emby
    kill "$EMBY_PID" 2>/dev/null || true
    wait "$EMBY_PID" 2>/dev/null || true
    sleep 2
fi

# Patch BaseUrl into system.xml
if [ -f "$EMBY_SYSTEM_XML" ]; then
    if grep -q "<BaseUrl>" "$EMBY_SYSTEM_XML"; then
        sed -i 's|<BaseUrl>[^<]*</BaseUrl>|<BaseUrl>/emby</BaseUrl>|' "$EMBY_SYSTEM_XML"
    else
        sed -i 's|</ServerConfiguration>|  <BaseUrl>/emby</BaseUrl>\n</ServerConfiguration>|' "$EMBY_SYSTEM_XML"
    fi
    echo "Emby BaseUrl set to /emby"
fi

# ------------------------------------------
# Configure Alist
# ------------------------------------------
ALIST_CONFIG="/config/alist/config.json"
if [ ! -f "$ALIST_CONFIG" ]; then
    echo "Generating Alist default config..."
    cd /config/alist && /usr/local/bin/alist admin random --data /config/alist 2>/dev/null || true
fi

# Set Alist to listen on /alist base path via site_url
if [ -f "$ALIST_CONFIG" ] && command -v jq &> /dev/null; then
    # Set site_url for subpath routing
    jq '.site_url = "/alist"' "$ALIST_CONFIG" > /tmp/alist_config.json \
        && mv /tmp/alist_config.json "$ALIST_CONFIG"
    echo "Alist site_url set to /alist"
fi

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
