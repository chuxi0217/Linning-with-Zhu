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
import signal
import subprocess
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
LOG = os.path.expanduser("~/zanjia-tunnel.log")
HEARTBEAT = os.path.expanduser("~/.zanjia_tunnel_heartbeat")
ERRFILE = os.path.expanduser("~/.zanjia_tunnel_ssh_err")

# 9-29 断网教训（00:32–00:51 那次 502）：**网络断**时 ssh 是「秒退」的，旧启发式把"秒退"
# 一律当"端口被占"→ 退避翻倍到 60s 并卡在那儿，于是断网期间 19 分钟才接回。
# 现在按退出原因分流：断网类 → 快重试（等网回来）；端口占用类 → 才退避。
_NET_DOWN_PAT = ("no route to host", "network is unreachable", "temporary failure in name resolution",
                 "connection timed out", "operation timed out", "not responding",
                 "connection reset", "connection refused", "broken pipe",
                 "kex_exchange_identification", "closed by remote host")


def _is_net_down(err_text):
    e = (err_text or "").lower()
    return any(p in e for p in _NET_DOWN_PAT)


def _retry_delay(err_text, stable, delay, fast=5, cap=60):
    """下一轮重连等待秒数（纯函数，便于套件测）。
    - 活过 ≥60 秒的真断线 → fast（不倒退）；
    - 退出信息像"断网"（No route to host / not responding…）→ fast（网一回来自动好，别干等）；
    - 认不出来（多为 VPS 侧端口占用等）→ 退避加倍（cap 封顶），防每 5 秒白刷。"""
    if stable >= 6 or _is_net_down(err_text):
        return fast
    return min(max(int(delay), fast) * 2, cap)


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


def _is_self_forward(args, marker):
    """一行 ps 的 args 是不是「自家反隧道 ssh」——必须 -N 且命令行含精确转发串。纯函数，便于套件。"""
    return bool(args) and args.startswith("ssh ") and " -N " in args and (marker in args)


def _kill_stale_self(marker):
    """清掉**自家残留**的反隧道 ssh。

    9-29 02:06–02:21 实案：server 重启后 `_ensure_tunnel` 拉起新管理器，可**上一条 ssh 还活着**
    （成了孤儿），VPS 那头的端口被它占着 → 新管理器每次都 "remote port forwarding failed"，
    退避 60 秒空转十几分钟（门其实还通，靠的就是那条孤儿）。换管理器时先清掉自家的，端口就腾出来了。
    只杀命令行**精确匹配**那个转发串的 ssh；绝不碰别的 ssh 会话。返回清掉的条数。"""
    n = 0
    try:
        out = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True, text=True,
                             timeout=5).stdout
    except Exception:
        return 0
    me = os.getpid()
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        pid_s, args = parts
        if not _is_self_forward(args, marker):
            continue
        try:
            pid = int(pid_s)
        except Exception:
            continue
        if pid == me:
            continue
        try:
            os.kill(pid, signal.SIGTERM)
            n += 1
            _log(f"清掉自家残留 ssh（pid {pid}）——它占着 VPS 那头的 {marker}")
        except Exception as e:
            _log(f"清残留 ssh 失手（pid {pid}）：{e}")
    return n


def main():
    vps = str(_cfg("vps", "root@your-vps.example"))
    rport = str(_cfg("remote_port", "18024"))
    lport = str(_cfg("local_port", "8024"))
    cmd = ["ssh", "-N",
           "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=3",
           "-o", "ConnectTimeout=10", "-o", "ExitOnForwardFailure=yes", "-o", "BatchMode=yes",
           "-R", f"{rport}:127.0.0.1:{lport}", vps]
    _log(f"保活启动：{' '.join(cmd)}")
    # 9-27 随身 WiFi 教训：弱网抖掉后，VPS 侧半死连接会把端口占一会儿（"forwarding failed"
    # 死循环、每 5 秒白试一分钟）。
    # 9-29 加固：退避改**按退出原因分流**（见 _retry_delay）——断网类快重试、其余才退避；
    # 并用 ConnectTimeout=10 让"连不上"快速失败（默认 TCP 超时要等两分钟）。
    fast = int(_cfg("retry_fast", 5))
    cap = int(_cfg("retry_max", 60))
    marker = f"{rport}:127.0.0.1:{lport}"
    _kill_stale_self(marker)      # 启动先清自家孤儿（换管理器时最常见）
    delay = fast
    while True:
        err_text = ""
        try:
            _beat()
            with open(ERRFILE, "w", encoding="utf-8") as ef:
                p = subprocess.Popen(cmd, stderr=ef, **_hide_kw())
                stable = 0
                while p.poll() is None:   # 连着的时候：每 10 秒续心跳
                    _beat()
                    time.sleep(10)
                    stable += 1
            try:
                with open(ERRFILE, encoding="utf-8", errors="replace") as ef:
                    err_text = ef.read()[-400:]
            except Exception:
                err_text = ""
            delay = _retry_delay(err_text, stable, delay, fast=fast, cap=cap)
            if "remote port forwarding failed" in err_text.lower():
                _kill_stale_self(marker)   # 端口被自家孤儿占着 → 当场清掉再重试
            why = "断网/超时" if (stable < 6 and _is_net_down(err_text)) else (
                "长命掉线" if stable >= 6 else "端口占用/未知")
            _log(f"ssh 掉了（退出码 {p.returncode}·{why}），{delay} 秒后重连"
                 + (f"｜{err_text.strip().splitlines()[-1][:80]}" if err_text.strip() else ""))
        except Exception as e:
            delay = min(max(int(delay), fast) * 2, cap)
            _log(f"拉起失败（{e}），{delay} 秒后重试")
        _beat()
        time.sleep(delay)


if __name__ == "__main__":
    main()
