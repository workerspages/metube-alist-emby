#!/bin/bash
# Rclone mount script: Mount Alist WebDAV to /media/alist for Emby
# This script waits for Alist to be ready, then mounts its WebDAV endpoint

MOUNT_POINT="/media/alist"
ALIST_URL="http://localhost:5244/dav/"
ALIST_USER="${ALIST_USER:-admin}"
ALIST_PASS="${ALIST_PASS:-}"

echo "[rclone-mount] Waiting for Alist to be ready..."

# Wait for Alist to start (max 120s)
for i in $(seq 1 120); do
    if curl -s -o /dev/null -w '%{http_code}' "http://localhost:5244/api/public/settings" 2>/dev/null | grep -q "200"; then
        echo "[rclone-mount] Alist is ready."
        break
    fi
    sleep 1
done

# If no password provided, try to read from Alist config
if [ -z "$ALIST_PASS" ]; then
    echo "[rclone-mount] No ALIST_PASS set. Alist WebDAV requires authentication."
    echo "[rclone-mount] Set ALIST_PASS environment variable or configure via Alist web UI."
    echo "[rclone-mount] Attempting mount with guest access..."
    ALIST_USER="guest"
    ALIST_PASS=""
fi

mkdir -p "$MOUNT_POINT"

echo "[rclone-mount] Mounting Alist WebDAV ($ALIST_URL) to $MOUNT_POINT ..."

exec rclone mount :webdav: "$MOUNT_POINT" \
    --webdav-url "$ALIST_URL" \
    --webdav-vendor other \
    --webdav-user "$ALIST_USER" \
    --webdav-pass "$(rclone obscure "$ALIST_PASS" 2>/dev/null || echo "")" \
    --allow-other \
    --allow-non-empty \
    --dir-cache-time 5m \
    --vfs-cache-mode full \
    --vfs-cache-max-age 1h \
    --vfs-read-chunk-size 8M \
    --buffer-size 32M \
    --no-modtime \
    --log-level INFO
