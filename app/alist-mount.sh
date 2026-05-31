#!/bin/bash
# Alist WebDAV rclone mount 脚本
# 将 Alist 的 WebDAV 接口通过 FUSE 挂载到本地目录
# 仅在 ALIST_MOUNT_MODE=mount 时运行，否则休眠

if [ "$ALIST_MOUNT_MODE" != "mount" ]; then
    echo "[alist-mount] 当前模式: ${ALIST_MOUNT_MODE:-未设置}，rclone mount 已禁用"
    exec sleep infinity
fi

echo "[alist-mount] rclone mount 模式已激活"
echo "[alist-mount] 等待 Alist 服务启动..."

# 等待 Alist 就绪（最多 60 秒）
RETRY=0
while [ $RETRY -lt 12 ]; do
    if curl -sf http://localhost:5244/alist/api/public/settings >/dev/null 2>&1; then
        echo "[alist-mount] Alist 已就绪"
        break
    fi
    RETRY=$((RETRY + 1))
    sleep 5
done

if [ $RETRY -ge 12 ]; then
    echo "[alist-mount] ⚠️ Alist 启动超时，仍然尝试挂载..."
fi

# 确保挂载点存在
mkdir -p /media/alist

# 构建 rclone mount 命令
# --allow-other: 允许其他用户（如 Emby）访问挂载目录
# --vfs-cache-mode minimal: 仅缓存打开的文件元数据，节省磁盘
# --vfs-read-chunk-size: 按需读取块大小，适合视频流
# --dir-cache-time: 目录缓存时间，减少 API 请求
RCLONE_ARGS=(
    "--webdav-url" "http://localhost:5244/alist/dav"
    "--webdav-user" "${ALIST_USER:-admin}"
    "--allow-other"
    "--allow-non-empty"
    "--vfs-cache-mode" "minimal"
    "--vfs-read-chunk-size" "32M"
    "--vfs-read-chunk-size-limit" "256M"
    "--dir-cache-time" "5m"
    "--attr-timeout" "5m"
    "--buffer-size" "64M"
    "--log-level" "INFO"
)

# 如果设置了密码，添加密码参数
if [ -n "${ALIST_ADMIN_PASS}" ]; then
    RCLONE_ARGS+=("--webdav-pass" "$(rclone obscure "${ALIST_ADMIN_PASS}")")
fi

echo "[alist-mount] 挂载 Alist WebDAV → /media/alist"
exec rclone mount :webdav: /media/alist "${RCLONE_ARGS[@]}"
