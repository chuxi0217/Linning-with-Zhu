#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GALATEA-01（2026-09-13 工单）：Galatea Garden 唤醒桥 injector。

单向门铃线的一端（军规⑤：数据不出门）——官方 bridge（galatea-garden-wake-bridge）把园子
事件原样喂进本脚本 stdin（一行 UTF-8 JSON），本脚本只做一件事：转投咱家 /api/world_event，
让事件进世界事件队列（叫醒由 server 的 _garden_loop 走，本脚本不负责唤醒）。

输入（bridge 原样喂）：
  {"version": 1, "type": "garden_wake", "reason": "...", "message": "..."}
转投：
  POST http://127.0.0.1:8024/api/world_event
  {"kind": "galatea", "summary": message[:120]（空则 reason 兜底）, "evidence": {"reason": reason}}

成败口径（锁死规格）：
  · 只有 HTTP 2xx 算成功——stdout 一行 [galatea] 事件已进门 #id，退出码 0；
  · 读不到/非 JSON/字段缺/没话可传 → 退出码 2 + stderr 一句短错因；
  · 超时 10s / 连不上 / 非 2xx → 退出码 3 + stderr 一句短错因。
  bridge 侧有自己的有界重试；咱家接受极小概率双投递（重复即两条相近事件，她静默其一，不拦）。

纪律：纯标准库；不读 config.json、不碰库、不落文件。
"""

import json
import sys
import urllib.error
import urllib.request

TARGET_URL = "http://127.0.0.1:8024/api/world_event"   # 锁死（GALATEA-01 规格）：本机正式门
HTTP_TIMEOUT_S = 10


def _die(msg, code):
    sys.stderr.write(f"[galatea] {msg}\n")
    sys.exit(code)


def main():
    line = sys.stdin.buffer.readline()
    if not line.strip():
        _die("stdin 没读到内容", 2)
    try:
        text = line.decode("utf-8")
    except UnicodeDecodeError:
        _die("不是 UTF-8", 2)
    try:
        obj = json.loads(text)
    except ValueError:
        _die("不是 JSON", 2)
    if not isinstance(obj, dict):
        _die("JSON 不是对象", 2)
    for key in ("version", "type", "reason", "message"):
        if key not in obj:
            _die(f"字段缺：{key}", 2)
    if obj.get("version") != 1:
        _die(f"version 不是 1（{obj.get('version')!r}）", 2)
    if obj.get("type") != "garden_wake":
        _die(f"type 不是 garden_wake（{obj.get('type')!r}）", 2)
    reason = obj.get("reason")
    message = obj.get("message")
    if not isinstance(reason, str) or not isinstance(message, str):
        _die("reason/message 得是字符串", 2)
    summary = (message.strip() or reason.strip())[:120]
    if not summary:
        _die("没话可传（message 与 reason 都空）", 2)

    body = json.dumps(
        {"kind": "galatea", "summary": summary, "evidence": {"reason": reason}},
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        TARGET_URL, data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            payload = resp.read()
            status = resp.getcode()
    except urllib.error.HTTPError as e:
        _die(f"家里拒收：HTTP {e.code}", 3)
    except Exception as e:   # URLError / 超时 / 连接拒绝……都算投递失败，交给 bridge 的那一次重试
        _die(f"投递失败：{str(e)[:100]}", 3)
    if not (200 <= status < 300):
        _die(f"家里拒收：HTTP {status}", 3)

    wid = None
    try:
        wid = json.loads(payload.decode("utf-8")).get("id")
    except Exception:
        wid = None
    if wid is not None:
        print(f"[galatea] 事件已进门 #{wid}")
    else:
        print("[galatea] 事件已进门")
    sys.exit(0)


if __name__ == "__main__":
    main()
