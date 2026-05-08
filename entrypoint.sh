#!/bin/bash
set -e

echo "=========================================="
echo "  MeTube + Alist + Emby All-in-One"
echo "=========================================="

# Create necessary directories
mkdir -p /downloads /config/alist /config/emby/config /config/emby/data

# ------------------------------------------
# Configure Emby base URL
# ------------------------------------------
EMBY_SYSTEM_XML="/config/emby/config/system.xml"
if [ ! -f "$EMBY_SYSTEM_XML" ]; then
    echo "Creating Emby config with BaseUrl=/emby ..."
    cat > "$EMBY_SYSTEM_XML" << 'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<ServerConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <BaseUrl>/emby</BaseUrl>
  <HttpServerPortNumber>8096</HttpServerPortNumber>
  <PublicPort>8080</PublicPort>
</ServerConfiguration>
XMLEOF
fi

# ------------------------------------------
# Configure Alist site_url
# ------------------------------------------
ALIST_CONFIG="/config/alist/config.json"
if [ ! -f "$ALIST_CONFIG" ]; then
    echo "Generating Alist default config ..."
    cd /config/alist && /usr/local/bin/alist admin random --data /config/alist 2>/dev/null || true
fi

# Update Alist site_url if config exists
if [ -f "$ALIST_CONFIG" ] && command -v jq &> /dev/null; then
    CURRENT_SITE_URL=$(jq -r '.site_url // ""' "$ALIST_CONFIG" 2>/dev/null || echo "")
    if [ "$CURRENT_SITE_URL" != "/alist" ]; then
        echo "Setting Alist site_url to /alist ..."
        jq '.site_url = "/alist"' "$ALIST_CONFIG" > /tmp/alist_config.json \
            && mv /tmp/alist_config.json "$ALIST_CONFIG"
    fi
fi

echo "Starting all services via supervisord ..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
