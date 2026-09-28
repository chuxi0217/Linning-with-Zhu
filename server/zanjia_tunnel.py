#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""zanjia_tunnel.py —— 咱家反向隧道保活（跨平台版 · 9-25 · Linux/Windows 通用）

和 ~/zanjia-tunnel.sh 同一个活：把 VPS 的 127.0.0.1:18024 反指到本机 :8024。
重连策略（9-27 弱网加固）：长命连接掉线→5 秒快重连；短命连接反复掉（端口占用）→
退避加倍 5→10→20→40→60 封顶；连稳 60 秒后复位。换掉了 pgrep/bash，Windows 也能用
（server 通电会自动拉起它）。

心跳：~/.zanjia_tunnel_heartbeat（循环里持续写时间戳）——
server 的 _tunnel_probe 认它当探针（跨平台；Windows 没有 pgrep）。

用法：python3 zanjia_tunnel.py（server 通电自动拉起；也可手动跑）
可调：环境变量 ZANJIA_TUNNEL_VPS / ZANJIA_TUNNEL_REMOTE_PORT / ZANJIA_TUNNEL_LOCAL_PORT
      （其次 config.json 的 tunnel_vps / tunnel_remote_port / tunnel_local_port）
"""
import json
import os
import subprocess
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
LOG = os.path.expanduser("~/zanjia-tunnel.log")
HEARTBEAT = os.path.expanduser("~/.zanjia_tunnel_heartbeat")


def _cfg(key, default):
    """取值：环境变量优先（ZANJIA_TUNNEL_X），其次 config.json（tunnel_x），最后默认。"""
    env = os.environ.get("ZANJIA_TUNNEL_" + key.upper())
    if env:
        return env
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get("tunnel_" + key, default)
    except Exception:
        return default


def _log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"[{time.strftime('%F %T')}] {msg}\n")
    except Exception:
        pass


def _beat():
    """心跳：探针认这个文件的新鲜度。"""
    try:
        with open(HEARTBEAT, "w", encoding="utf-8") as f:
            f.write(time.strftime("%F %T"))
    except Exception:
        pass


def _hide_kw():
    """Windows：ssh 子进程不弹黑窗（CREATE_NO_WINDOW＋隐藏 STARTUPINFO）；Linux 返回空。
    9-25 弹窗修：ssh 每次失败重试都曾闪一个控制台窗（隧道无钥匙时每 15s 一次）。"""
    if os.name != "nt":
        return {}
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0
    return {"creationflags": 0x08000000, "startupinfo": si}


def main():
    vps = str(_cfg("vps", "root@your-vps.example"))
    rport = str(_cfg("remote_port", "18024"))
    lport = str(_cfg("local_port", "8024"))
    cmd = ["ssh", "-N",
           "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=3",
           "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
           "-R", f"{rport}:127.0.0.1:{lport}", vps]
    _log(f"保活启动：{' '.join(cmd)}")
    # 9-27 随身 WiFi 教训：弱网抖掉后，VPS 侧半死连接会把端口占一会儿（"forwarding failed"
    # 死循环、每 5 秒白试一分钟）。改为：长命连接掉线→仍 5 秒快重连（不倒退）；
    # 短命连接反复掉（端口占用典型）→ 退避加倍 5→10→20→40→60 封顶；连稳 60 秒后退避复位。
    delay = 5
    while True:
        try:
            _beat()
            p = subprocess.Popen(cmd, **_hide_kw())
            stable = 0
            while p.poll() is None:   # 连着的时候：每 10 秒续心跳
                _beat()
                time.sleep(10)
                stable += 1
            if stable >= 6:           # 活过 ≥60 秒：算真断线，保留 5 秒快重连
                delay = 5
            else:                     # 短命连接（端口占用等）：退避加倍，别白刷
                delay = min(max(delay, 5) * 2, 60)
            _log(f"ssh 掉了（退出码 {p.returncode}），{delay} 秒后重连")
        except Exception as e:
            delay = min(max(delay, 5) * 2, 60)
            _log(f"拉起失败（{e}），{delay} 秒后重试")
        _beat()
        time.sleep(delay)


if __name__ == "__main__":
    main()
