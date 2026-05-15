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
            rsync -a --delete "$PERSIST_DIR/$dir/" "$RUN_DIR/$dir/"
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
            rsync -a --delete "$RUN_DIR/$dir/" "$PERSIST_DIR/$dir/"
        fi
    done
    echo "[db-sync] Sync complete."
}

# 首次启动时的恢复逻辑
if [ "$1" = "restore" ]; then
    sync_to_run
    exit 0
fi

# 捕获 SIGTERM 信号，用于在容器停止时进行最后一次安全备份
trap 'echo "[db-sync] Received SIGTERM. Performing final sync..."; sync_to_persist; exit 0' TERM INT

echo "[db-sync] Starting background sync loop (every 5 minutes)..."
while true; do
    # 使用后台 sleep 并 wait，以便 trap 能立即响应中断信号
    sleep 300 & wait $!
    sync_to_persist
done
