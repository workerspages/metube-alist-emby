#!/bin/bash
# Emby 媒体库自动扫描脚本
# 监听 /media 目录的文件变化，当有新文件加入时自动通知 Emby 刷新媒体库
# 依赖：inotifywait (inotify-tools)
# 如未安装 inotify-tools 则每 5 分钟轮询刷新一次（备用模式）

EMBY_HOST="http://localhost:8096"
EMBY_API_KEY="${EMBY_API_KEY:-}"
WATCH_DIR="/media"
# 防抖延迟：最后一个文件写入后等待 N 秒再触发，避免下载中频繁触发
DEBOUNCE_SECONDS=30

trigger_emby_scan() {
    if [ -z "$EMBY_API_KEY" ]; then
        echo "[emby-scan-watcher] EMBY_API_KEY 未设置，跳过自动扫描"
        return
    fi
    echo "[emby-scan-watcher] 触发 Emby 媒体库刷新..."
    curl -sf -X POST \
        "${EMBY_HOST}/emby/Library/Refresh?api_key=${EMBY_API_KEY}" \
        -H "Content-Type: application/json" \
        > /dev/null 2>&1 && echo "[emby-scan-watcher] Emby 媒体库刷新请求已发送" \
        || echo "[emby-scan-watcher] Emby 刷新请求失败，请检查 EMBY_API_KEY 和 Emby 状态"
}

# 优先使用 inotifywait 实时监听
if command -v inotifywait &>/dev/null; then
    echo "[emby-scan-watcher] 使用 inotifywait 实时监听 $WATCH_DIR"
    LAST_TRIGGER=0
    while true; do
        # 监听文件关闭事件（即写入完成）
        inotifywait -r -e close_write,moved_to,create "$WATCH_DIR" -q --format '%w%f' 2>/dev/null
        NOW=$(date +%s)
        ELAPSED=$(( NOW - LAST_TRIGGER ))
        if [ "$ELAPSED" -ge "$DEBOUNCE_SECONDS" ]; then
            trigger_emby_scan
            LAST_TRIGGER=$NOW
        fi
    done
else
    # 备用：无 inotifywait 时每 5 分钟轮询一次
    echo "[emby-scan-watcher] inotifywait 未安装，备用模式：每 5 分钟轮询刷新一次"
    while true; do
        sleep 300
        trigger_emby_scan
    done
fi
