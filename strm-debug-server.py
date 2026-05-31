#!/usr/bin/env python3
"""
STRM Sync 诊断服务器
提供 Web 界面查看 Alist 连接状态、STRM 同步日志和 /media/alist 目录内容
"""
import os
import json
import time
import urllib.request
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

ALIST_URL = "http://localhost:5244/alist"
ALIST_USER = os.environ.get("ALIST_USER", "admin")
# 直接复用 ALIST_ADMIN_PASS，无需额外设置 ALIST_PASS
ALIST_PASS = os.environ.get("ALIST_ADMIN_PASS", "")
MOUNT_POINT = "/media/alist"
DEBUG_PORT = 9090


def check_alist_api():
    """检查 Alist API 是否可达"""
    try:
        req = urllib.request.urlopen(f"{ALIST_URL}/api/public/settings", timeout=5)
        data = json.loads(req.read())
        return {"status": "ok", "code": data.get("code"), "message": data.get("message", "")}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def check_alist_login():
    """检查 Alist 登录认证"""
    if not ALIST_PASS:
        return {"status": "skip", "message": "ALIST_ADMIN_PASS 未设置，跳过登录测试"}
    try:
        req = urllib.request.Request(f"{ALIST_URL}/api/auth/login", method="POST")
        req.add_header("Content-Type", "application/json")
        data = json.dumps({"username": ALIST_USER, "password": ALIST_PASS}).encode()
        with urllib.request.urlopen(req, data=data, timeout=5) as resp:
            res = json.loads(resp.read())
            if res.get("code") == 200:
                return {"status": "ok", "message": "登录成功", "has_token": bool(res.get("data", {}).get("token"))}
            else:
                return {"status": "error", "code": res.get("code"), "message": res.get("message", "未知错误")}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def get_alist_token():
    """获取 Alist token，供内部调用使用"""
    if not ALIST_PASS:
        return ""
    try:
        req = urllib.request.Request(f"{ALIST_URL}/api/auth/login", method="POST")
        req.add_header("Content-Type", "application/json")
        data = json.dumps({"username": ALIST_USER, "password": ALIST_PASS}).encode()
        with urllib.request.urlopen(req, data=data, timeout=5) as resp:
            res = json.loads(resp.read())
            if res.get("code") == 200:
                return res["data"]["token"]
    except Exception:
        pass
    return ""


def check_alist_root_listing():
    """检查 Alist 根目录内容（测试存储挂载）"""
    try:
        token = get_alist_token()
        req = urllib.request.Request(f"{ALIST_URL}/api/fs/list", method="POST")
        req.add_header("Content-Type", "application/json")
        if token:
            req.add_header("Authorization", token)
        data = json.dumps({"path": "/", "password": "", "page": 1, "per_page": 0, "refresh": False}).encode()
        with urllib.request.urlopen(req, data=data, timeout=10) as resp:
            res = json.loads(resp.read())
            if res.get("code") == 200:
                content = res.get("data", {}).get("content") or []
                items = [{"name": i["name"], "is_dir": i["is_dir"], "size": i.get("size", 0)} for i in content]
                return {"status": "ok", "item_count": len(items), "items": items}
            else:
                return {"status": "error", "code": res.get("code"), "message": res.get("message", "")}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def list_local_media():
    """列出 /media/alist 下的文件"""
    result = {"dirs": [], "strm_files": [], "other_files": []}
    if not os.path.exists(MOUNT_POINT):
        return {"status": "error", "message": f"{MOUNT_POINT} 不存在"}

    total_strm = 0
    for root, dirs, files in os.walk(MOUNT_POINT):
        rel_root = os.path.relpath(root, MOUNT_POINT)
        if rel_root == ".":
            rel_root = ""
        for d in dirs:
            result["dirs"].append(os.path.join(rel_root, d) if rel_root else d)
        for f in files:
            fpath = os.path.join(rel_root, f) if rel_root else f
            if f.endswith(".strm"):
                total_strm += 1
                if total_strm <= 50:
                    full_path = os.path.join(root, f)
                    try:
                        with open(full_path, "r") as sf:
                            content = sf.read().strip()
                    except:
                        content = "<读取失败>"
                    result["strm_files"].append({"path": fpath, "url": content})
            else:
                result["other_files"].append(fpath)

    result["total_strm_count"] = total_strm
    result["total_dirs"] = len(result["dirs"])
    result["status"] = "ok"
    return result


def check_supervisor_status():
    """检查 supervisord 各服务状态"""
    try:
        import subprocess
        # supervisorctl status 在有服务非 RUNNING 时返回退出码 3，属正常行为
        proc = subprocess.run(
            ["supervisorctl", "status"], capture_output=True, text=True, timeout=5
        )
        lines = proc.stdout.strip().split("\n")
        services = []
        for line in lines:
            parts = line.split()
            if len(parts) >= 2:
                services.append({"name": parts[0], "status": parts[1], "detail": " ".join(parts[2:])})
        return {"status": "ok", "services": services}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def get_sync_log():
    """读取 STRM 同步的最近日志"""
    log_file = "/var/log/alist-strm-sync.log"
    try:
        if not os.path.exists(log_file):
            return {"status": "ok", "log": "（日志文件尚未创建）"}
        with open(log_file, "r", errors="replace") as f:
            f.seek(0, 2)
            size = f.tell()
            read_size = min(size, 5000)
            f.seek(max(0, size - read_size))
            content = f.read()
        return {"status": "ok", "log": content or "（日志为空）"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def check_emby_plugins():
    """检查 Emby 插件目录内容"""
    plugin_dir = "/opt/emby-server/system/plugins"
    result = {"plugin_dir": plugin_dir, "files": [], "dirs": []}
    if not os.path.exists(plugin_dir):
        return {"status": "error", "plugin_dir": plugin_dir, "message": f"目录不存在: {plugin_dir}"}
    try:
        for item in sorted(os.listdir(plugin_dir)):
            full_path = os.path.join(plugin_dir, item)
            if os.path.isfile(full_path):
                size = os.path.getsize(full_path)
                result["files"].append({"name": item, "size": size})
            elif os.path.isdir(full_path):
                sub_items = os.listdir(full_path)
                result["dirs"].append({"name": item, "contents": sub_items})
        result["status"] = "ok"
    except Exception as e:
        result["status"] = "error"
        result["message"] = str(e)
    return result


def get_emby_log():
    """读取 Emby 最近日志（查找插件加载信息）"""
    programdata = os.environ.get("EMBY_PROGRAMDATA", "/config/emby")
    log_dir = os.path.join(programdata, "logs")
    if not os.path.exists(log_dir):
        return {"status": "error", "message": f"日志目录不存在: {log_dir}"}
    try:
        log_files = [f for f in os.listdir(log_dir) if f.endswith(".txt") or f.endswith(".log")]
        if not log_files:
            return {"status": "ok", "log": "（无日志文件）"}
        log_files.sort(key=lambda f: os.path.getmtime(os.path.join(log_dir, f)), reverse=True)
        latest = os.path.join(log_dir, log_files[0])
        with open(latest, "r", errors="replace") as f:
            f.seek(0, 2)
            size = f.tell()
            read_size = min(size, 8000)
            f.seek(max(0, size - read_size))
            content = f.read()
        plugin_lines = []
        for line in content.split("\n"):
            low = line.lower()
            if "plugin" in low or "metatube" in low or "strmassistant" in low or "assembly" in low or "loaded" in low:
                plugin_lines.append(line)
        return {"status": "ok", "log_file": log_files[0],
                "plugin_lines": "\n".join(plugin_lines[-30:]) if plugin_lines else "（未找到插件相关日志）",
                "full_tail": content[-3000:]}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def get_env_info():
    """获取相关环境变量（脱敏）"""
    keys = ["ALIST_USER", "ALIST_DATA", "EMBY_PROGRAMDATA", "TZ"]
    env = {}
    for k in keys:
        env[k] = os.environ.get(k, "<未设置>")
    env["ALIST_ADMIN_PASS"] = "***已设置***" if os.environ.get("ALIST_ADMIN_PASS") else "<空>"
    return env


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>STRM Sync 诊断</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body {
    font-family: 'Segoe UI', 'SF Pro', system-ui, -apple-system, sans-serif;
    background: #0a0e1a;
    color: #e2e8f0;
    min-height: 100vh;
    padding: 1.5rem;
}
.header {
    text-align: center;
    margin-bottom: 2rem;
}
.header h1 {
    font-size: 1.8rem;
    background: linear-gradient(90deg, #f59e0b, #ef4444, #ec4899);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    margin-bottom: 0.3rem;
}
.header p { color: #64748b; font-size: 0.9rem; }
.back { display:inline-block; color:#60a5fa; text-decoration:none; margin-bottom:1rem; font-size:0.9rem; }
.back:hover { text-decoration: underline; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 1.2rem; margin-bottom: 1.5rem; }
.card {
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 12px;
    padding: 1.2rem;
    overflow: hidden;
}
.card h2 {
    font-size: 1rem;
    color: #94a3b8;
    margin-bottom: 0.8rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
}
.badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 99px;
    font-size: 0.75rem;
    font-weight: 600;
}
.badge.ok { background: rgba(34,197,94,0.15); color: #22c55e; }
.badge.error { background: rgba(239,68,68,0.15); color: #ef4444; }
.badge.skip { background: rgba(234,179,8,0.15); color: #eab308; }
.badge.running { background: rgba(59,130,246,0.15); color: #3b82f6; }
.kv { margin: 0.4rem 0; font-size: 0.85rem; }
.kv .key { color: #64748b; min-width: 120px; display: inline-block; }
.kv .val { color: #e2e8f0; word-break: break-all; }
.file-list {
    max-height: 300px;
    overflow-y: auto;
    font-size: 0.8rem;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    background: rgba(0,0,0,0.3);
    border-radius: 8px;
    padding: 0.8rem;
    line-height: 1.6;
}
.file-list .dir { color: #60a5fa; }
.file-list .strm { color: #34d399; }
.file-list .url { color: #64748b; font-size: 0.75rem; margin-left: 1rem; display: block; }
.log-box {
    max-height: 400px;
    overflow-y: auto;
    font-size: 0.78rem;
    font-family: 'Cascadia Code', 'Fira Code', monospace;
    background: rgba(0,0,0,0.4);
    border-radius: 8px;
    padding: 0.8rem;
    white-space: pre-wrap;
    word-break: break-all;
    line-height: 1.5;
    color: #a3b8cc;
}
.full-width { grid-column: 1 / -1; }
table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
table th { text-align: left; color: #64748b; padding: 0.3rem 0.5rem; border-bottom: 1px solid rgba(255,255,255,0.08); }
table td { padding: 0.3rem 0.5rem; }
.item-list { max-height: 200px; overflow-y: auto; font-size: 0.83rem; }
.item-row { padding: 0.2rem 0; display: flex; gap: 1rem; }
.item-row .name { color: #e2e8f0; }
.item-row .meta { color: #64748b; font-size: 0.78rem; }
.refresh-btn {
    display: inline-block;
    margin-top: 1rem;
    padding: 0.5rem 1.5rem;
    background: linear-gradient(135deg, #3b82f6, #6366f1);
    color: #fff;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    font-size: 0.9rem;
    text-decoration: none;
}
.refresh-btn:hover { opacity: 0.9; }
.svc-btn {
    padding: 1px 6px;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.7rem;
    font-weight: 600;
    transition: all 0.15s ease;
    line-height: 1.5;
    white-space: nowrap;
}
.svc-btn:hover { opacity: 0.85; }
.svc-btn:active { transform: scale(0.95); }
.svc-btn:disabled { opacity: 0.35; cursor: not-allowed; transform: none; }
.svc-btn.stop { background: rgba(239,68,68,0.3); color: #fca5a5; }
.svc-btn.stop:hover { background: rgba(239,68,68,0.5); }
.svc-btn.start { background: rgba(34,197,94,0.3); color: #86efac; }
.svc-btn.start:hover { background: rgba(34,197,94,0.5); }
.svc-btn.restart { background: rgba(59,130,246,0.3); color: #93c5fd; }
.svc-btn.restart:hover { background: rgba(59,130,246,0.5); }
.svc-btn.loading { opacity: 0.5; cursor: wait; }
.svc-actions { display: flex; gap: 4px; flex-wrap: wrap; }
.timestamp { text-align: center; color: #475569; font-size: 0.8rem; margin-top: 1rem; }
</style>
</head>
<body>
<a href="/" class="back">← 返回门户</a>
<div class="header">
    <h1>🔧 STRM Sync 诊断面板</h1>
    <p>Alist 网盘连接状态 & STRM 同步排查</p>
</div>
<div id="content">加载中...</div>
<div style="text-align:center"><a href="/debug/" class="refresh-btn">🔄 刷新</a></div>
<p class="timestamp">生成时间: __TIMESTAMP__</p>
<script>
const data = __DATA__;

function badge(status) {
    const map = {ok:'ok',error:'error',skip:'skip',RUNNING:'running',STOPPED:'error',FATAL:'error'};
    return `<span class="badge ${map[status]||'skip'}">${status}</span>`;
}

function render() {
    let html = '<div class="grid">';

    // 1. Alist API
    html += `<div class="card"><h2>🌐 Alist API 连通性 ${badge(data.alist_api.status)}</h2>`;
    if (data.alist_api.status === 'ok') {
        html += `<div class="kv"><span class="key">响应码:</span> <span class="val">${data.alist_api.code}</span></div>`;
    } else {
        html += `<div class="kv"><span class="key">错误:</span> <span class="val" style="color:#ef4444">${data.alist_api.message}</span></div>`;
    }
    html += '</div>';

    // 2. Alist 登录
    html += `<div class="card"><h2>🔑 Alist 登录认证 ${badge(data.alist_login.status)}</h2>`;
    html += `<div class="kv"><span class="key">结果:</span> <span class="val">${data.alist_login.message || ''}</span></div>`;
    if (data.alist_login.has_token !== undefined) {
        html += `<div class="kv"><span class="key">Token:</span> <span class="val">${data.alist_login.has_token ? '✅ 已获取' : '❌ 无'}</span></div>`;
    }
    html += '</div>';

    // 3. Alist 根目录
    html += `<div class="card"><h2>📂 Alist 根目录内容 ${badge(data.alist_root.status)}</h2>`;
    if (data.alist_root.status === 'ok') {
        html += `<div class="kv"><span class="key">挂载数量:</span> <span class="val">${data.alist_root.item_count}</span></div>`;
        if (data.alist_root.item_count === 0) {
            html += `<div class="kv"><span class="val" style="color:#eab308">⚠️ Alist 根目录为空！请先在 Alist 中添加存储驱动（网盘）</span></div>`;
        } else {
            html += '<div class="item-list">';
            data.alist_root.items.forEach(i => {
                const icon = i.is_dir ? '📁' : '📄';
                const size = i.is_dir ? '' : ` (${(i.size/1024/1024).toFixed(1)}MB)`;
                html += `<div class="item-row"><span class="name">${icon} ${i.name}${size}</span></div>`;
            });
            html += '</div>';
        }
    } else {
        html += `<div class="kv"><span class="val" style="color:#ef4444">${data.alist_root.message}</span></div>`;
    }
    html += '</div>';

    // 4. 环境变量
    html += '<div class="card"><h2>⚙️ 环境变量</h2>';
    Object.entries(data.env).forEach(([k, v]) => {
        html += `<div class="kv"><span class="key">${k}:</span> <span class="val">${v}</span></div>`;
    });
    html += '</div>';

    // 5. 服务状态
    html += `<div class="card"><h2>🏗️ Supervisor 服务状态 ${badge(data.supervisor.status)}</h2>`;
    if (data.supervisor.status === 'ok') {
        html += '<table><tr><th>服务</th><th>状态</th><th>详情</th><th>操作</th></tr>';
        data.supervisor.services.forEach(s => {
            const isRunning = s.status === 'RUNNING';
            const isSelf = s.name === 'strm-debug';
            let actionHtml = '<div class="svc-actions">';
            if (isRunning) {
                actionHtml += `<button class="svc-btn stop" onclick="toggleService('${s.name}','stop')" ${isSelf ? 'disabled title="不能停止诊断面板自身"' : ''}>停止</button>`;
                actionHtml += `<button class="svc-btn restart" onclick="toggleService('${s.name}','restart')">重启</button>`;
            } else {
                actionHtml += `<button class="svc-btn start" onclick="toggleService('${s.name}','start')">启动</button>`;
            }
            actionHtml += '</div>';
            html += `<tr><td>${s.name}</td><td>${badge(s.status)}</td><td>${s.detail}</td><td>${actionHtml}</td></tr>`;
        });
        html += '</table>';
    } else {
        html += `<div class="kv"><span class="val" style="color:#ef4444">${data.supervisor.message}</span></div>`;
    }
    html += '</div>';

    // 6. 本地媒体目录
    html += `<div class="card"><h2>💾 /media/alist 目录 ${badge(data.local_media.status)}</h2>`;
    if (data.local_media.status === 'ok') {
        html += `<div class="kv"><span class="key">STRM 文件:</span> <span class="val">${data.local_media.total_strm_count} 个</span></div>`;
        html += `<div class="kv"><span class="key">目录:</span> <span class="val">${data.local_media.total_dirs} 个</span></div>`;
        if (data.local_media.total_strm_count === 0 && data.local_media.total_dirs === 0) {
            html += `<div class="kv"><span class="val" style="color:#eab308">⚠️ 目录为空！STRM 同步可能还未执行或 Alist 中无视频文件</span></div>`;
        }
        if (data.local_media.dirs.length > 0 || data.local_media.strm_files.length > 0) {
            html += '<div class="file-list">';
            data.local_media.dirs.forEach(d => { html += `<span class="dir">📁 ${d}</span>\\n`; });
            data.local_media.strm_files.forEach(f => {
                html += `<span class="strm">📺 ${f.path}</span><span class="url">→ ${f.url}</span>`;
            });
            html += '</div>';
        }
    } else {
        html += `<div class="kv"><span class="val" style="color:#ef4444">${data.local_media.message}</span></div>`;
    }
    html += '</div>';

    html += '</div>'; // grid

    // 7. Emby 插件目录
    if (data.emby_plugins) {
        html += `<div class="card full-width"><h2>🔌 Emby 插件目录 ${badge(data.emby_plugins.status)}</h2>`;
        html += `<div class="kv"><span class="key">路径:</span> <span class="val">${data.emby_plugins.plugin_dir}</span></div>`;
        if (data.emby_plugins.status === 'ok') {
            if (data.emby_plugins.files.length > 0) {
                html += '<div class="kv"><span class="key">DLL 文件:</span></div>';
                html += '<div class="file-list">';
                data.emby_plugins.files.forEach(f => {
                    const sizeKB = (f.size / 1024).toFixed(1);
                    const isMetaTube = f.name.toLowerCase().includes('metatube');
                    const isStrmAssistant = f.name.toLowerCase().includes('strmassistant');
                    const color = (isMetaTube || isStrmAssistant) ? '#22c55e' : '#e2e8f0';
                    html += `<span style="color:${color}">📦 ${f.name} (${sizeKB} KB)</span>\n`;
                });
                html += '</div>';
            } else {
                html += `<div class="kv"><span class="val" style="color:#eab308">⚠️ plugins 目录下没有 DLL 文件</span></div>`;
            }
            if (data.emby_plugins.dirs.length > 0) {
                html += '<div class="kv"><span class="key">子目录:</span></div>';
                html += '<div class="file-list">';
                data.emby_plugins.dirs.forEach(d => {
                    html += `<span class="dir">📁 ${d.name}/ → [${d.contents.join(', ')}]</span>\n`;
                });
                html += '</div>';
            }
        } else {
            html += `<div class="kv"><span class="val" style="color:#ef4444">${data.emby_plugins.message}</span></div>`;
        }
        html += '</div>';
    }

    // 8. Emby 插件日志
    if (data.emby_log) {
        html += '<div class="card full-width"><h2>📋 Emby 插件加载日志</h2>';
        if (data.emby_log.status === 'ok') {
            if (data.emby_log.log_file) html += `<div class="kv"><span class="key">日志文件:</span> <span class="val">${data.emby_log.log_file}</span></div>`;
            html += `<div class="log-box">${data.emby_log.plugin_lines || '（暂无）'}</div>`;
        } else {
            html += `<div class="kv"><span class="val" style="color:#ef4444">${data.emby_log.message}</span></div>`;
        }
        html += '</div>';
    }

    // 9. 同步日志
    html += '<div class="card full-width"><h2>📋 STRM 同步日志（最近）</h2>';
    if (data.sync_log.status === 'ok') {
        html += `<div class="log-box">${data.sync_log.log || '（暂无日志）'}</div>`;
    } else {
        html += `<div class="kv"><span class="val" style="color:#ef4444">${data.sync_log.message}</span></div>`;
    }
    html += '</div>';

    document.getElementById('content').innerHTML = html;
}

render();

async function toggleService(name, action) {
    const btn = event.target;
    btn.disabled = true;
    btn.classList.add('loading');
    const origText = btn.textContent;
    btn.textContent = '⏳ 处理中…';
    try {
        const resp = await fetch(`/debug/api/service/${action}`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({service: name})
        });
        const result = await resp.json();
        if (result.status !== 'ok') {
            alert('操作失败: ' + (result.message || '未知错误'));
        }
        // 刷新服务状态
        const diagResp = await fetch('/debug/api/supervisor');
        const diagData = await diagResp.json();
        data.supervisor = diagData;
        render();
    } catch (e) {
        alert('请求失败: ' + e.message);
        btn.textContent = origText;
        btn.disabled = false;
        btn.classList.remove('loading');
    }
}
</script>
</body>
</html>"""


class DebugHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path.startswith("/?"):
            diag = {
                "alist_api": check_alist_api(),
                "alist_login": check_alist_login(),
                "alist_root": check_alist_root_listing(),
                "local_media": list_local_media(),
                "supervisor": check_supervisor_status(),
                "sync_log": get_sync_log(),
                "env": get_env_info(),
                "emby_plugins": check_emby_plugins(),
                "emby_log": get_emby_log(),
            }
            ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            # 防 XSS：转义 JSON 中的 < 字符，防止 </script> 注入
            safe_json = json.dumps(diag, ensure_ascii=False).replace("<", "\\u003c")
            page = HTML_TEMPLATE.replace("__DATA__", safe_json)
            page = page.replace("__TIMESTAMP__", ts)
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(page.encode("utf-8"))
        elif self.path == "/api/diagnose":
            diag = {
                "alist_api": check_alist_api(),
                "alist_login": check_alist_login(),
                "alist_root": check_alist_root_listing(),
                "local_media": list_local_media(),
                "supervisor": check_supervisor_status(),
                "sync_log": get_sync_log(),
                "env": get_env_info(),
                "emby_plugins": check_emby_plugins(),
                "emby_log": get_emby_log(),
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(diag, ensure_ascii=False, indent=2).encode("utf-8"))
        elif self.path == "/api/supervisor":
            diag = check_supervisor_status()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(diag, ensure_ascii=False).encode("utf-8"))
        elif self.path == "/api/trigger-sync":
            try:
                import subprocess
                subprocess.Popen(["supervisorctl", "restart", "alist-strm-sync"])
                resp = {"status": "ok", "message": "同步服务已重启"}
            except Exception as e:
                resp = {"status": "error", "message": str(e)}
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(resp, ensure_ascii=False).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    # 允许的服务白名单（与 supervisord.conf 中定义的服务名一致）
    ALLOWED_SERVICES = {
        "caddy", "emby", "metube", "alist", "alist-strm-sync",
        "strm-debug", "qbittorrent", "metatube-server", "rclone-webdav",
        "emby-scan-watcher"
    }

    def do_POST(self):
        if self.path in ("/api/service/stop", "/api/service/start", "/api/service/restart"):
            action = self.path.rsplit("/", 1)[-1]  # stop / start / restart
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(content_length)) if content_length else {}
                service = body.get("service", "")

                # 安全校验
                if service not in self.ALLOWED_SERVICES:
                    resp = {"status": "error", "message": f"未知服务: {service}"}
                elif action == "stop" and service == "strm-debug":
                    resp = {"status": "error", "message": "不能停止诊断面板自身"}
                else:
                    import subprocess
                    result = subprocess.run(
                        ["supervisorctl", action, service],
                        capture_output=True, text=True, timeout=10
                    )
                    if result.returncode == 0:
                        action_name = {"stop": "停止", "start": "启动", "restart": "重启"}.get(action, action)
                        resp = {"status": "ok", "message": f"{service} 已{action_name}"}
                    else:
                        resp = {"status": "error", "message": result.stdout.strip() or result.stderr.strip()}
            except Exception as e:
                resp = {"status": "error", "message": str(e)}

            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.end_headers()
            self.wfile.write(json.dumps(resp, ensure_ascii=False).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 静默日志


if __name__ == "__main__":
    print(f"Debug server starting on port {DEBUG_PORT}...")
    server = HTTPServer(("0.0.0.0", DEBUG_PORT), DebugHandler)
    server.serve_forever()
