#!/usr/bin/env python3
import os
import time
import urllib.request
import urllib.parse
import json
import logging
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s',
                    handlers=[
                        logging.StreamHandler(),
                        logging.FileHandler("/var/log/alist-strm-sync.log", encoding="utf-8"),
                    ])

ALIST_BASE = "/alist"
ALIST_URL = f"http://localhost:5244{ALIST_BASE}"
ALIST_USER = os.environ.get("ALIST_USER", "admin")
# 直接复用 ALIST_ADMIN_PASS，无需额外设置 ALIST_PASS
ALIST_PASS = os.environ.get("ALIST_ADMIN_PASS", "")
# Caddy 内部代理注入的 Basic Auth 串（容器内存，不落盘）
ALIST_AUTH_B64 = os.environ.get("ALIST_AUTH_B64", "")
MOUNT_POINT = "/media/alist"
CADDY_PORT = 8080

# 视频格式后缀
VIDEO_EXTS = {".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".ts", ".m2ts", ".iso", ".rmvb"}

def get_token():
    if not ALIST_PASS:
        logging.warning("ALIST_ADMIN_PASS 未设置，将以匿名身份访问 Alist（可能失败）")
        return ""
    req = urllib.request.Request(f"{ALIST_URL}/api/auth/login", method="POST")
    req.add_header("Content-Type", "application/json")
    data = json.dumps({"username": ALIST_USER, "password": ALIST_PASS}).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=data) as response:
            res = json.loads(response.read())
            if res.get("code") == 200:
                return res["data"]["token"]
            else:
                logging.error(f"Alist login failed: {res.get('message')}")
    except Exception as e:
        logging.error(f"Alist login failed: {e}")
    return ""

def list_dir(path, token):
    req = urllib.request.Request(f"{ALIST_URL}/api/fs/list", method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    data = json.dumps({"path": path, "password": "", "page": 1, "per_page": 10000, "refresh": False}).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=data) as response:
            res = json.loads(response.read())
            if res.get("code") == 200:
                return res["data"].get("content") or []
            else:
                logging.warning(f"List dir {path} returned code {res.get('code')}: {res.get('message')}")
    except Exception as e:
        logging.error(f"List dir {path} failed: {e}")
    return None

def build_strm_url(item_path):
    """构建 .strm 文件内容

    安全设计（修复密码泄露 BUG）：
    - 优先通过 Caddy 内部代理 /alist-dav-serve 播放，
      Basic Auth 由 Caddy 从容器环境变量注入（凭据不写入文件）
    - ALIST_AUTH_B64 未设置时回退到无凭据匿名直连（不包含任何认证信息）
    """
    quoted_path = urllib.parse.quote(item_path)
    if ALIST_AUTH_B64:
        # 通过 Caddy 注入认证，.strm 文件内不包含用户/密码
        return f"http://127.0.0.1:{CADDY_PORT}/alist-dav-serve{alist_dav_path(quoted_path)}"
    else:
        # 匿名访问（无凭据）
        return f"http://127.0.0.1:5244{alist_dav_path(quoted_path)}"

def alist_dav_path(quoted_path):
    """Alist WebDAV 路径拼接（兼容 /alist 前缀）"""
    return f"{ALIST_BASE}/dav{quoted_path}"

def write_strm_if_changed(strm_filepath, expected_url):
    """仅在文件不存在或内容不一致时写入，避免同名覆盖和密码变更后不更新"""
    existing = None
    if os.path.exists(strm_filepath):
        try:
            with open(strm_filepath, "r", encoding="utf-8") as f:
                existing = f.read().strip()
        except Exception:
            existing = None

    if existing != expected_url:
        try:
            with open(strm_filepath, "w", encoding="utf-8") as f:
                f.write(expected_url)
            if existing is None:
                logging.info(f"Created STRM: {strm_filepath}")
            else:
                logging.info(f"Updated STRM (内容已变化): {strm_filepath}")
            return True
        except Exception as e:
            logging.error(f"Failed to write {strm_filepath}: {e}")
    return False

def sync():
    # 检查 Alist 是否已启动
    try:
        urllib.request.urlopen(f"{ALIST_URL}/api/public/settings", timeout=5)
    except:
        return  # Alist 未启动，稍后再试

    token = get_token()
    valid_strm_files = set()

    def traverse(current_path):
        content = list_dir(current_path, token)
        if content is None:
            return

        # 本地创建对应目录
        local_dir = os.path.join(MOUNT_POINT, current_path.lstrip("/"))
        os.makedirs(local_dir, exist_ok=True)

        for item in content:
            name = item["name"]
            item_path = f"{current_path}/{name}" if current_path != "/" else f"/{name}"

            if item["is_dir"]:
                traverse(item_path)
            else:
                ext = os.path.splitext(name)[1].lower()
                if ext in VIDEO_EXTS:
                    # 带完整文件名生成 .strm（如 movie.mkv.strm），
                    # 避免同名不同扩展名的视频互相覆盖（修复 BUG）
                    strm_filename = name + ".strm"
                    strm_filepath = os.path.join(local_dir, strm_filename)
                    valid_strm_files.add(strm_filepath)

                    expected_url = build_strm_url(item_path)
                    write_strm_if_changed(strm_filepath, expected_url)

    logging.info("Starting STRM sync scan...")
    traverse("/")
    logging.info("Scan complete. Cleaning up old STRM files...")

    # 清理已不存在的文件
    for root, dirs, files in os.walk(MOUNT_POINT):
        for file in files:
            if file.endswith(".strm"):
                filepath = os.path.join(root, file)
                if filepath not in valid_strm_files:
                    try:
                        os.remove(filepath)
                        logging.info(f"Removed old STRM: {filepath}")
                    except Exception as e:
                        logging.error(f"Failed to remove {filepath}: {e}")

    # 清理空目录（自底向上）
    for root, dirs, files in os.walk(MOUNT_POINT, topdown=False):
        if root == MOUNT_POINT:
            continue
        if not os.listdir(root):
            try:
                os.rmdir(root)
                logging.info(f"Removed empty dir: {root}")
            except Exception as e:
                logging.error(f"Failed to remove dir {root}: {e}")


if __name__ == "__main__":
    # rclone mount 模式下无需 STRM 同步
    if os.environ.get("ALIST_MOUNT_MODE") == "mount":
        logging.info("rclone mount 模式已激活，STRM 同步已禁用（Emby 直接读取挂载目录）")
        import signal
        signal.pause()

    logging.info("Alist STRM sync service started. Waiting for Alist initialization...")
    time.sleep(10)  # 启动时等待10秒
    while True:
        try:
            sync()
        except Exception as e:
            logging.error(f"Sync task error: {e}")
        time.sleep(300)  # 每 5 分钟同步一次