#!/usr/bin/env python3
import os
import time
import urllib.request
import urllib.parse
import json
import logging
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')

ALIST_URL = "http://localhost:5244"
ALIST_USER = os.environ.get("ALIST_USER", "admin")
ALIST_PASS = os.environ.get("ALIST_PASS", "")
MOUNT_POINT = "/media/alist"

# 视频格式后缀
VIDEO_EXTS = {".mp4", ".mkv", ".avi", ".mov", ".wmv", ".flv", ".webm", ".ts", ".m2ts", ".iso", ".rmvb"}

def get_token():
    if not ALIST_PASS:
        return ""
    req = urllib.request.Request(f"{ALIST_URL}/api/auth/login", method="POST")
    req.add_header("Content-Type", "application/json")
    data = json.dumps({"username": ALIST_USER, "password": ALIST_PASS}).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=data) as response:
            res = json.loads(response.read())
            if res.get("code") == 200:
                return res["data"]["token"]
    except Exception as e:
        logging.error(f"Alist login failed: {e}")
    return ""

def list_dir(path, token):
    req = urllib.request.Request(f"{ALIST_URL}/api/fs/list", method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    data = json.dumps({"path": path, "password": "", "page": 1, "per_page": 0, "refresh": False}).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=data) as response:
            res = json.loads(response.read())
            if res.get("code") == 200:
                return res["data"].get("content") or []
    except Exception as e:
        logging.error(f"List dir {path} failed: {e}")
    return None

def sync():
    # 检查 Alist 是否已启动
    try:
        urllib.request.urlopen(f"{ALIST_URL}/api/public/settings", timeout=5)
    except:
        return # Alist 未启动，稍后再试

    token = get_token()
    valid_strm_files = set()
    
    def traverse(current_path):
        content = list_dir(current_path, token)
        if content is None: return
        
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
                    # 使用 WebDAV 路径，携带 basic auth 供 Emby 直接读取并重定向播放
                    auth_part = f"{urllib.parse.quote(ALIST_USER)}:{urllib.parse.quote(ALIST_PASS)}@" if ALIST_PASS else ""
                    # quote 处理路径中的特殊字符或中文
                    quoted_path = urllib.parse.quote(item_path)
                    strm_url = f"http://{auth_part}127.0.0.1:5244/dav{quoted_path}"
                    
                    strm_filename = os.path.splitext(name)[0] + ".strm"
                    strm_filepath = os.path.join(local_dir, strm_filename)
                    valid_strm_files.add(strm_filepath)
                    
                    if not os.path.exists(strm_filepath):
                        try:
                            with open(strm_filepath, "w", encoding="utf-8") as f:
                                f.write(strm_url)
                            logging.info(f"Created STRM: {strm_filepath}")
                        except Exception as e:
                            logging.error(f"Failed to create {strm_filepath}: {e}")

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

if __name__ == "__main__":
    logging.info("Alist STRM sync service started. Waiting for Alist initialization...")
    time.sleep(10) # 启动时等待10秒
    while True:
        try:
            sync()
        except Exception as e:
            logging.error(f"Sync task error: {e}")
        time.sleep(300) # 每 5 分钟同步一次
