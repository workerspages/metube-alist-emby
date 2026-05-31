#!/usr/bin/env python3
"""
STRM 视频截图生成服务
扫描 /media/alist 下的 .strm 文件，使用 ffmpeg 从远程视频流中截取画面
生成 Emby 可自动识别的缩略图文件（<文件名>-thumb.jpg）

仅在 ALIST_MOUNT_MODE=strm 时运行，mount 模式下 Emby 原生 Image Capture 可用
"""
import os
import time
import subprocess
import logging
import signal
import sys

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/var/log/strm-thumb-gen.log", encoding="utf-8"),
    ]
)

MOUNT_POINT = "/media/alist"

# ffmpeg 截取参数
SEEK_PRIMARY = 60       # 首选截取位置（秒）
SEEK_FALLBACK = 5       # 回退截取位置（秒）
JPEG_QUALITY = 5        # JPEG 质量（2=最佳, 31=最差, 5≈85%）
MAX_WIDTH = 1280        # 最大宽度限制（px），保持纵横比
FFMPEG_TIMEOUT = 30     # ffmpeg 单次执行超时时间（秒）

# 同步间隔
SCAN_INTERVAL = 300     # 扫描间隔（秒）
INITIAL_DELAY = 30      # 启动延迟（秒），等待 alist-strm-sync 先生成 .strm 文件


def capture_thumbnail(video_url, output_path, seek_seconds):
    """使用 ffmpeg 从视频 URL 截取一帧画面

    Args:
        video_url: 视频文件的 URL（通常是 Alist WebDAV 地址）
        output_path: 输出缩略图路径
        seek_seconds: 跳转到指定秒数截取

    Returns:
        True 成功, False 失败
    """
    cmd = [
        "ffmpeg",
        "-ss", str(seek_seconds),       # 快速 seek（放在 -i 前面）
        "-i", video_url,                # 输入 URL
        "-vframes", "1",                # 只截取 1 帧
        "-q:v", str(JPEG_QUALITY),      # JPEG 质量
        "-vf", f"scale='min({MAX_WIDTH},iw)':-2",  # 限制最大宽度
        "-y",                           # 覆盖已有文件
        output_path
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=FFMPEG_TIMEOUT
        )
        if result.returncode == 0 and os.path.exists(output_path):
            size = os.path.getsize(output_path)
            if size > 0:
                return True
            else:
                # 生成了空文件，清理掉
                os.remove(output_path)
                return False
        return False
    except subprocess.TimeoutExpired:
        logging.warning(f"ffmpeg 超时 ({FFMPEG_TIMEOUT}s): {output_path}")
        # 清理可能的不完整文件
        if os.path.exists(output_path):
            os.remove(output_path)
        return False
    except Exception as e:
        logging.error(f"ffmpeg 执行失败: {e}")
        if os.path.exists(output_path):
            os.remove(output_path)
        return False


def get_thumb_path(strm_path):
    """根据 .strm 文件路径生成对应的缩略图路径

    Emby 命名规则: <文件名>-thumb.jpg
    例如: 电影.strm -> 电影-thumb.jpg
    """
    base = os.path.splitext(strm_path)[0]
    return base + "-thumb.jpg"


def scan_and_generate():
    """扫描 .strm 文件并生成缺失的缩略图"""
    if not os.path.exists(MOUNT_POINT):
        logging.warning(f"挂载点不存在: {MOUNT_POINT}")
        return

    # 收集所有 .strm 文件
    strm_files = []
    for root, dirs, files in os.walk(MOUNT_POINT):
        for f in files:
            if f.endswith(".strm"):
                strm_files.append(os.path.join(root, f))

    if not strm_files:
        logging.info("未发现 .strm 文件，跳过")
        return

    # 统计
    total = len(strm_files)
    skipped = 0
    success = 0
    failed = 0

    logging.info(f"开始扫描，共发现 {total} 个 .strm 文件")

    for strm_path in strm_files:
        thumb_path = get_thumb_path(strm_path)

        # 已有缩略图，跳过
        if os.path.exists(thumb_path):
            skipped += 1
            continue

        # 读取 .strm 文件中的视频 URL
        try:
            with open(strm_path, "r", encoding="utf-8") as f:
                video_url = f.read().strip()
        except Exception as e:
            logging.error(f"读取 .strm 文件失败: {strm_path}: {e}")
            failed += 1
            continue

        if not video_url:
            logging.warning(f".strm 文件为空: {strm_path}")
            failed += 1
            continue

        rel_path = os.path.relpath(strm_path, MOUNT_POINT)
        logging.info(f"截图中: {rel_path}")

        # 先尝试在 SEEK_PRIMARY 秒处截取
        if capture_thumbnail(video_url, thumb_path, SEEK_PRIMARY):
            size_kb = os.path.getsize(thumb_path) / 1024
            logging.info(f"✅ 截图成功 ({size_kb:.1f}KB): {rel_path}")
            success += 1
        # 回退到 SEEK_FALLBACK 秒处
        elif capture_thumbnail(video_url, thumb_path, SEEK_FALLBACK):
            size_kb = os.path.getsize(thumb_path) / 1024
            logging.info(f"✅ 截图成功 (回退到{SEEK_FALLBACK}s, {size_kb:.1f}KB): {rel_path}")
            success += 1
        else:
            logging.warning(f"❌ 截图失败: {rel_path}")
            failed += 1

    logging.info(f"扫描完成: 总计={total}, 新截图={success}, 已有={skipped}, 失败={failed}")

    # 清理孤立的缩略图（.strm 已删除但 -thumb.jpg 还在）
    cleanup_orphaned_thumbs()


def cleanup_orphaned_thumbs():
    """清理已失去对应 .strm 文件的孤立缩略图"""
    removed = 0
    for root, dirs, files in os.walk(MOUNT_POINT):
        for f in files:
            if f.endswith("-thumb.jpg"):
                thumb_path = os.path.join(root, f)
                # 反推对应的 .strm 文件名
                strm_name = f.replace("-thumb.jpg", ".strm")
                strm_path = os.path.join(root, strm_name)
                if not os.path.exists(strm_path):
                    try:
                        os.remove(thumb_path)
                        logging.info(f"清理孤立缩略图: {os.path.relpath(thumb_path, MOUNT_POINT)}")
                        removed += 1
                    except Exception as e:
                        logging.error(f"清理失败: {thumb_path}: {e}")

    if removed > 0:
        logging.info(f"共清理 {removed} 个孤立缩略图")


if __name__ == "__main__":
    # rclone mount 模式下无需截图服务
    if os.environ.get("ALIST_MOUNT_MODE") == "mount":
        logging.info("rclone mount 模式已激活，ffmpeg 截图服务已禁用（Emby 原生 Image Capture 可用）")
        signal.pause()

    logging.info(f"ffmpeg 截图服务已启动 (ALIST_MOUNT_MODE=strm)")
    logging.info(f"参数: 截取位置={SEEK_PRIMARY}s(回退{SEEK_FALLBACK}s), 质量={JPEG_QUALITY}, 最大宽度={MAX_WIDTH}px")
    logging.info(f"等待 {INITIAL_DELAY} 秒，让 STRM 同步先完成...")
    time.sleep(INITIAL_DELAY)

    while True:
        try:
            scan_and_generate()
        except Exception as e:
            logging.error(f"截图任务异常: {e}")
        time.sleep(SCAN_INTERVAL)
