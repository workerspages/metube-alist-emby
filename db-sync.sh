#!/bin/bash
# SQLite PaaS Sync Script
# 用于在 PaaS 持久卷和容器本地运行时目录之间同步数据，防止 SQLite 损坏

PERSIST_DIR="/config"
RUN_DIR="/app/data"

# 需要同步的目录
SYNC_DIRS=("alist" "emby" "qBittorrent")

sync_to_run() {
    echo "[db-sync] Restoring from persistent volume to local run directory..."
    for dir in "${SYNC_DIRS[@]}"; do
        if [ -d "$PERSIST_DIR/$dir" ]; then
            mkdir -p "$RUN_DIR/$dir"
            if command -v sqlite3 >/dev/null 2>&1 && { [ "$dir" = "emby" ] || [ "$dir" = "alist" ]; }; then
                # Always clean up leftover WAL files in the persistent directory before restoring
                # This prevents previous dirty shutdowns or leftover WALs from corrupting the fresh start
                find "$PERSIST_DIR/$dir" -type f \( -name "*.db-wal" -o -name "*.db-shm" \) -delete 2>/dev/null || true
                rsync -a --delete --exclude="*.db-wal" --exclude="*.db-shm" "$PERSIST_DIR/$dir/" "$RUN_DIR/$dir/"
            else
                rsync -a --delete "$PERSIST_DIR/$dir/" "$RUN_DIR/$dir/"
            fi
        else
            mkdir -p "$RUN_DIR/$dir"
        fi
    done
    echo "[db-sync] Restore complete."
}

sync_to_persist() {
    echo "[db-sync] Syncing local run directory to persistent volume..."
    for dir in "${SYNC_DIRS[@]}"; do
        if [ -d "$RUN_DIR/$dir" ]; then
            mkdir -p "$PERSIST_DIR/$dir"
            
            if command -v sqlite3 >/dev/null 2>&1 && { [ "$dir" = "emby" ] || [ "$dir" = "alist" ]; }; then
                # Safe backup for SQLite DBs (Emby/Alist)
                # First, sync everything EXCEPT the databases and WALs
                rsync -a --delete --exclude="*.db" --exclude="*.db-wal" --exclude="*.db-shm" "$RUN_DIR/$dir/" "$PERSIST_DIR/$dir/"
                
                # Find all .db files recursively in the run directory and back them up safely
                # 使用 -print0 + read -d '' 处理路径含空格的情况（修复 R2）
                while IFS= read -r -d '' db_path; do
                    rel_path="${db_path#$RUN_DIR/$dir/}"
                    target_dir="$PERSIST_DIR/$dir/$(dirname "$rel_path")"
                    mkdir -p "$target_dir"
                    # Use sqlite3 .backup for an atomic snapshot
                    sqlite3 "$db_path" ".backup '$target_dir/$(basename "$db_path")'" || echo "[WARN] Failed to backup $db_path"
                done < <(find "$RUN_DIR/$dir" -type f -name "*.db" -print0)
                
                # Clean up any old WAL/SHM files in the persistent volume to prevent restore conflicts
                find "$PERSIST_DIR/$dir" -type f \( -name "*.db-wal" -o -name "*.db-shm" \) -delete 2>/dev/null || true
            else
                rsync -a --delete "$RUN_DIR/$dir/" "$PERSIST_DIR/$dir/"
            fi
        fi
    done
    echo "[db-sync] Sync complete."
}

# 首次启动时的恢复逻辑
if [ "$1" = "restore" ]; then
    sync_to_run
    exit 0
fi

# 移除 SIGTERM 的关机同步（trap），避免在 PaaS 平台强制关闭时 rsync 被 SIGKILL 中断导致持久化卷大面积损坏
# 完全依赖 5 分钟的定时脏备份 + 启动时的 sqlite3 .recover 自动修复机制

sync_to_webdav() {
    if [ -f /tmp/rclone-backup.conf ]; then
        echo "[db-sync] Syncing /config to WebDAV backup..."
        (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone sync --config /tmp/rclone-backup.conf /config/ backup:config/ || echo "[WARN] WebDAV sync for /config failed.")
        local EXCLUDE_ALIST=""
        if [ "$ALIST_MOUNT_MODE" = "mount" ]; then
            EXCLUDE_ALIST="--exclude alist/**"
        fi
        echo "[db-sync] Syncing /media to WebDAV backup (excluding partials)..."
        (unset RCLONE_WEBDAV_USER RCLONE_WEBDAV_PASS; rclone sync --config /tmp/rclone-backup.conf --exclude "*.!qB" --exclude "*.part" --exclude "*.ytdl" --exclude "temp/**"  /media/  $EXCLUDE_ALIST backup:media/ || echo "[WARN] WebDAV sync for /media failed.")
    fi
}

SYNC_INTERVAL=${WEBDAV_SYNC_INTERVAL:-300}
echo "[db-sync] Starting background sync loop (every ${SYNC_INTERVAL} seconds)..."
# 启动后先立即执行一次同步，防止短时间内崩溃丢失数据
sleep 60 && sync_to_persist && sync_to_webdav
while true; do
    # 使用后台 sleep 并 wait，以便 trap 能立即响应中断信号
    sleep ${SYNC_INTERVAL} & wait $!
    sync_to_persist
    sync_to_webdav
done
