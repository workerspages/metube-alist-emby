#!/bin/bash
# Emby 媒体库自动扫描脚本
# 监听 /media 目录的文件变化，当有新文件加入时自动通知 Emby 刷新媒体库
# 依赖：inotifywait (inotify-tools)
# 如未安装 inotify-tools 则每 5 分钟轮询刷新一次（备用模式）
#
# 修复说明（BUG B4）：
#   FUSE 挂载目录（rclone mount /media/alist）不会产生 inotify 事件，
#   因此在 mount 模式下额外启动一个对 /media/alist 的快照轮询线程，
#   与 inotifywait 互补，确保网盘新增文件也能触发 Emby 自动刷新。

EMBY_HOST="http://localhost:8096"
EMBY_API_KEY="${EMBY_API_KEY:-}"
WATCH_DIR="/media"
# 防抖延迟：最后一个文件写入后等待 N 秒无新事件才触发
DEBOUNCE_SECONDS=30
# FUSE 目录轮询间隔（秒）
FUSE_POLL_INTERVAL=30
# FUSE 挂载目录（仅 ALIST_MOUNT_MODE=mount 时需轮询）
ALIST_MOUNT_DIR="/media/alist"
ALIST_MOUNT_MODE="${ALIST_MOUNT_MODE:-auto}"

# 如果 EMBY_API_KEY 未设置，不启动监听（避免浪费资源）
if [ -z "$EMBY_API_KEY" ]; then
    echo "[emby-scan-watcher] EMBY_API_KEY 未设置，自动扫描已禁用。"
    echo "[emby-scan-watcher] 如需启用，请在环境变量中设置 EMBY_API_KEY。"
    # 保持进程存活但不做任何事，防止 supervisord 无限重启
    exec sleep infinity
fi

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

# FUSE 挂载目录快照轮询线程
# FUSE (rclone mount) 目录不产生 inotify 事件，只能通过定时对比文件列表检测变化
fuse_poll_watcher() {
    local prev_snapshot=""
    echo "[emby-scan-watcher] 启动 FUSE 目录轮询监测: $ALIST_MOUNT_DIR（间隔 ${FUSE_POLL_INTERVAL}s）"
    while true; do
        sleep "$FUSE_POLL_INTERVAL"
        # 仅当挂载目录实际存在且已被 rclone 挂载时轮询
        if [ -d "$ALIST_MOUNT_DIR" ]; then
            # 生成当前快照：相对路径 + 文件大小（忽略缩略图避免抖动）
            # 使用 find -printf 避免空目录问题；目录内容变化（新增/删除/改名）都会改变快照
            local cur_snapshot
            cur_snapshot=$(find "$ALIST_MOUNT_DIR" -type f ! -name "*-thumb.jpg" -printf "%P %s\n" 2>/dev/null | sort)
            if [ -n "$prev_snapshot" ] && [ "$cur_snapshot" != "$prev_snapshot" ]; then
                echo "[emby-scan-watcher] 检测到 FUSE 目录变化: $ALIST_MOUNT_DIR，等待防抖..."
                # 防抖：多次轮询确认目录稳定后再触发
                sleep "$DEBOUNCE_SECONDS"
                local cur2
                cur2=$(find "$ALIST_MOUNT_DIR" -type f ! -name "*-thumb.jpg" -printf "%P %s\n" 2>/dev/null | sort)
                if [ "$cur2" = "$cur_snapshot" ]; then
                    echo "[emby-scan-watcher] FUSE 目录已稳定，触发媒体库刷新"
                    trigger_emby_scan
                fi
                prev_snapshot="$cur2"
            else
                prev_snapshot="$cur_snapshot"
            fi
        fi
    done
}

# 优先使用 inotifywait 实时监听本地目录（/media/metube, /media/qbittorrent 等）
if command -v inotifywait &>/dev/null; then
    echo "[emby-scan-watcher] 使用 inotifywait 实时监听 $WATCH_DIR"
    PENDING=0
    LAST_EVENT=0

    # mount 模式下启动 FUSE 轮询线程（inotify 无法捕获 FUSE 事件）
    if [ "$ALIST_MOUNT_MODE" = "mount" ] && [ -d "$ALIST_MOUNT_DIR" ]; then
        fuse_poll_watcher &
        FUSE_POLL_PID=$!
        echo "[emby-scan-watcher] FUSE 轮询线程已启动 (PID: $FUSE_POLL_PID)"
    fi

    # 后台持续监听，将事件写入 FIFO
    FIFO=$(mktemp -u)
    mkfifo "$FIFO"
    inotifywait -r -m -e close_write,moved_to,create "$WATCH_DIR" \
        -q --format '%w%f' > "$FIFO" 2>/dev/null &
    INOTIFY_PID=$!

    # 清理 FIFO 和后台进程
    cleanup() {
        kill "$INOTIFY_PID" 2>/dev/null
        [ -n "${FUSE_POLL_PID:-}" ] && kill "$FUSE_POLL_PID" 2>/dev/null
        rm -f "$FIFO"
        exit 0
    }
    trap cleanup EXIT TERM INT

    # 非阻塞读取 FIFO，累积防抖
    while true; do
        # 尝试在 1 秒内读取一行（非阻塞轮询）
        if read -r -t 1 LINE < "$FIFO"; then
            PENDING=1
            LAST_EVENT=$(date +%s)
        fi

        # 如有待触发事件且已超过防抖时间，则触发
        if [ "$PENDING" -eq 1 ]; then
            NOW=$(date +%s)
            ELAPSED=$(( NOW - LAST_EVENT ))
            if [ "$ELAPSED" -ge "$DEBOUNCE_SECONDS" ]; then
                trigger_emby_scan
                PENDING=0
            fi
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