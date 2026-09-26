# -*- coding: utf-8 -*-
"""srv_static.py —— 静态资源与门锁 token（服务器拆分 P2 · 2026-09-25）

从 linning_server.py 原样搬出：网络门锁 token 放行（_gate_password/_image_token_ok）、
照片/收藏/附件落盘与安全路径（save_photo/photo_path_or_none/favorite_path_or_none/
favorites_list/save_file/file_path_or_none）。
纪律：目录常量与 datetime 运行期一律走 srv_state._srv()（沙盘会重绑 s.PHOTOS_DIR / s.FAVORITES_DIR /
s.FILES_DIR / s.GATE_CRED_PATH、换 s.datetime 假钟）；只做文件 IO 与 token 比对；fail-open。
入口重导出同名（Handler / rebuild_fts.py 引用照旧）。
"""

import base64
import hmac
import os
import re
import time
import urllib.parse
import uuid

import srv_state

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PHOTOS_DIR = os.path.join(BASE_DIR, "photos")
FAVORITES_DIR = os.path.join(BASE_DIR, "favorites")
FILES_DIR = os.path.join(BASE_DIR, "files")

# ── 照片落库：photos/ 子文件夹，时间戳+随机串 .jpg ──
# ── 网络门锁 token（9-23 新门配套·只放静态图）：鸿蒙 Image(url) 加不了自定义头，
# 公网图片直取必吃前置 Caddy basicauth 401 裂图。约定：图片 URL 带 ?token=<门锁密码
# 原串>（值在 网络门锁凭证.txt，app 线同源、两端各自读文件）= 等价 Basic 过。
# 只放 /photos/ /favorites/ 两处静态图；API 一律仍要 Basic 头——不开任何口子。
GATE_CRED_PATH = os.path.join(BASE_DIR, "网络门锁凭证.txt")
_GATE_CRED_CACHE = {"mtime": None, "pw": ""}


def _gate_password():
    """从 网络门锁凭证.txt 读门锁密码原串（按 mtime 缓存；读不到=空串=不放行）。
    格式=正文「密码：<值>」行；文件中没有该行或文件缺失都不炸——只是不放行。"""
    try:
        gate_path = srv_state._srv().GATE_CRED_PATH   # 运行期反查：沙盘会重绑 s.GATE_CRED_PATH
        stt = os.stat(gate_path)
        if _GATE_CRED_CACHE["mtime"] != stt.st_mtime:
            pw = ""
            with open(gate_path, encoding="utf-8", errors="replace") as f:
                for ln in f:
                    ln = ln.strip()
                    if ln.startswith("密码："):
                        pw = ln[3:].strip()   # len("密码：") == 3
                        break
            _GATE_CRED_CACHE.update({"mtime": stt.st_mtime, "pw": pw})
        return _GATE_CRED_CACHE["pw"]
    except OSError:
        return ""


def _image_token_ok(query):
    """静态图 token 放行判据：?token=<值> 与凭证密码原串恒时比较（compare_digest）。
    只认 token 一个参数，别的参数原样不碰。缺值/缺凭证/不等 → False。
    BE3-07（9-23 修复批）约定写死（App 线与服务端同源，别踩）：
    ① 只认名为 token 的**单个**参数，取第一个值；重复参数=取首个，别的参数一律不管。
    ② 值按**表单规则**解码（parse_qs）——门锁密码里若含 + 空格 & # % 这类字符，
       客户端必须整串 URL 编码（encodeURIComponent 口径），否则明文 + 会被解成空格、
       明明配对却 401。③ 不带 token=原逻辑照走（老门/局域网/浏览器）；带了但对不上=401。"""
    try:
        got = (urllib.parse.parse_qs(query or "").get("token") or [""])[0]
        want = _gate_password()
        return bool(want) and hmac.compare_digest(got.encode("utf-8"), want.encode("utf-8"))
    except Exception:
        return False


def save_photo(data_url):
    """把 dataURL 照片存进 photos/，返回文件名。格式不对抛 ValueError。"""
    prefix = "data:image/jpeg;base64,"
    if not isinstance(data_url, str) or not data_url.startswith(prefix):
        raise ValueError("不是咱家说好的 data:image/jpeg;base64, 格式")
    raw = base64.b64decode(data_url[len(prefix):], validate=True)
    srv = srv_state._srv()   # 运行期反查：沙盘会重绑 s.PHOTOS_DIR、换 s.datetime 假钟
    os.makedirs(srv.PHOTOS_DIR, exist_ok=True)
    name = srv.datetime.now().strftime("%Y%m%d_%H%M%S_") + uuid.uuid4().hex[:6] + ".jpg"
    with open(os.path.join(srv.PHOTOS_DIR, name), "wb") as f:
        f.write(raw)
    return name


def photo_path_or_none(name):
    """防路径穿越：只认 photos/ 里的纯白 .jpg 文件名，其余一律 None。"""
    name = urllib.parse.unquote(name).strip().split("?", 1)[0]
    if not name or name != os.path.basename(name) or not name.lower().endswith(".jpg"):
        return None
    pd = srv_state._srv().PHOTOS_DIR   # 运行期反查：沙盘会重绑 s.PHOTOS_DIR
    path = os.path.realpath(os.path.join(pd, name))
    if os.path.dirname(path) != os.path.realpath(pd):
        return None
    return path if os.path.isfile(path) else None


def favorite_path_or_none(name):
    """（9-4 自由发挥包）防穿越同款：只认 favorites/ 里的纯白 .jpg，其余一律 None。"""
    name = urllib.parse.unquote(name).strip().split("?", 1)[0]
    if not name or name != os.path.basename(name) or not name.lower().endswith(".jpg"):
        return None
    fd = srv_state._srv().FAVORITES_DIR   # 运行期反查：沙盘会重绑 s.FAVORITES_DIR
    path = os.path.realpath(os.path.join(fd, name))
    if os.path.dirname(path) != os.path.realpath(fd):
        return None
    return path if os.path.isfile(path) else None


def favorites_list():
    """（9-4 自由发挥包）收藏夹照片文件名，旧到新；夹不在=空。"""
    fd = srv_state._srv().FAVORITES_DIR   # 运行期反查：沙盘会重绑 s.FAVORITES_DIR
    if not os.path.isdir(fd):
        return []
    return sorted(f for f in os.listdir(fd) if f.lower().endswith(".jpg"))


# ── 文件附件落盘（二期 e，工单 9-1-#8）：files/ 子文件夹，时间戳_原文件名 ──
FILE_OK_EXT = (".txt", ".md", ".log")   # 只收文本件
FILE_MAX_BYTES = 32768                  # 32KB 全文上限（app 侧先拦，server 再验）


def save_file(name, content):
    """把文本附件存进 files/，返回落盘文件名。格式不对抛 ValueError。"""
    if not isinstance(name, str) or not name.strip():
        raise ValueError("附件得有文件名")
    base = os.path.basename(name.strip())   # 只认裸文件名
    if not base.lower().endswith(FILE_OK_EXT):
        raise ValueError("只收 .txt/.md/.log 文本件")
    if not isinstance(content, str):
        raise ValueError("附件内容得是文本")
    raw = content.encode("utf-8")
    if len(raw) > FILE_MAX_BYTES:
        raise ValueError("附件超 32KB")
    srv = srv_state._srv()   # 运行期反查：沙盘会重绑 s.FILES_DIR、换 s.datetime 假钟
    os.makedirs(srv.FILES_DIR, exist_ok=True)
    safe = re.sub(r"[\s/\\：:*?\"<>|〔〕]+", "_", base)[:80]
    saved = srv.datetime.now().strftime("%Y%m%d_%H%M%S_") + safe
    with open(os.path.join(srv.FILES_DIR, saved), "wb") as f:
        f.write(raw)
    return saved


def file_path_or_none(name):
    """防路径穿越（与照片同款）：只认 files/ 里的白名单后缀文件名，其余一律 None。"""
    name = urllib.parse.unquote(name).strip().split("?", 1)[0]
    if not name or name != os.path.basename(name) or not name.lower().endswith(FILE_OK_EXT):
        return None
    fd = srv_state._srv().FILES_DIR   # 运行期反查：沙盘会重绑 s.FILES_DIR
    path = os.path.realpath(os.path.join(fd, name))
    if os.path.dirname(path) != os.path.realpath(fd):
        return None
    return path if os.path.isfile(path) else None
