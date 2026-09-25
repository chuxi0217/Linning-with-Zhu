# -*- coding: utf-8 -*-
"""srv_books.py —— 共读导入解析 与 拒绝日志限速（服务器拆分 P2 · 2026-09-25）

从 linning_server.py 原样搬出：epub/html/txt 提字（_BookBad/_BookHTML/_book_tidy/
_book_decode/_book_html_to_text/_epub_to_text/_book_import_bytes）＋ Latent 拒绝日志
（_REJECT_* 常量与 _reject_line）。纯标准库；入口重导出同名（Handler 照旧引用）。
"""

import base64
import io
import os
import re
import threading
import time
import urllib.parse
import zipfile
from datetime import datetime
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

import memory_lib as m

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
# ── 共读导入·格式半边（9-23 共读格式批·服务端，家主令「共读支持 txt 以外格式」）──
# 契约（App 半边已按此冻结）：新字段 {"title","author","file_name","file_b64"}——
# file_name=原文件名带后缀、file_b64=原始字节 base64；epub/html 走这条提字路，
# txt/md 仍走老 content 路（老路一字不动，保旧客户端降级）。纯标准库
# （zipfile + html.parser + xml.etree）；书是导入物不进正典，落盘仍是 files/books/book_{id}.txt。


class _BookBad(Exception):
    """共读导入的「人话 400」：message 原样回给 app，不吐内部细节。"""


class _BookHTML(HTMLParser):
    """HTML/XHTML → 纯文本：script/style/head 整段丢（不吞正文里的同名词）；
    块级标签与 br 转换行；实体走 convert_charrefs（=html.unescape 同源）；空白收敛归 _book_tidy。"""

    _BLOCK = {"p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol", "tr",
              "td", "th", "table", "section", "article", "header", "footer", "figure",
              "figcaption", "blockquote", "pre", "hr", "nav", "aside", "main", "body", "html"}
    # 只列「有闭合标签」的整段丢：meta/link 这类空元素没有结束标签，进了这名单会把
    # _skip 永久顶高、把整篇正文吞掉（9-23 首跑 T3a 实案）。
    _SKIP = {"script", "style", "head"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in self._SKIP:
            self._skip += 1
        elif tag in self._BLOCK:
            self.parts.append("\n")

    def handle_startendtag(self, tag, attrs):
        if tag in self._BLOCK:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in self._SKIP and self._skip:
            self._skip -= 1
        elif tag in self._BLOCK:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self._skip and data:
            self.parts.append(data)

    def text(self):
        return "".join(self.parts)


def _book_tidy(raw):
    """空白收敛（App 端按空行切段：Index.ets split(/\\n\\s*\\n/)——段落之间留一个空行）：
    行尾去空、3+ 换行压成空行、整卷去首尾空。"""
    txt = (raw or "").replace("\r\n", "\n").replace("\r", "\n")
    txt = "\n".join(ln.rstrip() for ln in txt.split("\n"))
    return re.sub(r"\n{3,}", "\n\n", txt).strip()


def _book_decode(blob):
    """字节 → 文本：utf-8 先试，失败退 gbk，再失败 replace（宁要乱码不丢卷）。"""
    for enc in ("utf-8", "gbk"):
        try:
            return blob.decode(enc)
        except UnicodeDecodeError:
            continue
    return blob.decode("utf-8", errors="replace")


def _book_html_to_text(blob):
    """HTML/XHTML 字节 → 纯文本（剥标签 + 收敛）。解析器提不出字时退回正则粗剥
    （脏卷如没闭合的 <script> 会把解析器卡在 skip 态；退路再救一把，救不出仍交上层判 400）。"""
    src = _book_decode(blob)
    try:
        p = _BookHTML()
        p.feed(src)
        p.close()
        out = _book_tidy(p.text())
    except Exception:
        out = ""
    if out:
        return out
    src2 = re.sub(r"(?is)<(script|style|head)\b[^>]*>.*?</\1\s*>", " ", src)
    return _book_tidy(re.sub(r"<[^>]*>", " ", src2))


def _epub_zip_path(opf_dir, href):
    """zip 内部相对路径归一（epub href 归一到 zip 根的 posix 路径；先过 URL 解码）。"""
    rel = (opf_dir + "/" + urllib.parse.unquote(href or "")) if opf_dir else urllib.parse.unquote(href or "")
    out = []
    for seg in rel.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if out:
                out.pop()
            continue
        out.append(seg)
    return "/".join(out)


def _epub_to_text(blob):
    """epub（zip）→ (书名, 作者, 正文)：container.xml → OPF（dc:title/dc:creator + spine 顺序）→
    逐章 XHTML 提字（插图/封面页自然提不出字=略过）。带锁（META-INF/encryption.xml）或
    整本提不出字 → _BookBad 人话。"""
    try:
        zf = zipfile.ZipFile(io.BytesIO(blob))
        names = zf.namelist()
    except (zipfile.BadZipFile, OSError):
        raise _BookBad("这本书的文件像坏掉了（不是能打开的 epub）——换个版本试试")
    if "META-INF/encryption.xml" in names:
        raise _BookBad("这本还带着锁，打不开——换个无 DRM 的版本试试")
    opf_path = ""
    try:
        cx = zf.read("META-INF/container.xml").decode("utf-8", errors="replace")
    except KeyError:
        cx = ""
    m0 = (re.search(r'full-path\s*=\s*"([^"]+)"', cx)
          or re.search(r"full-path\s*=\s*'([^']+)'", cx))
    if m0:
        opf_path = m0.group(1)
    if not opf_path:
        for n in names:
            if n.lower().endswith(".opf"):
                opf_path = n
                break
    title = author = ""
    order = []
    opf_dir = opf_path.rsplit("/", 1)[0] if "/" in opf_path else ""
    try:
        opf_xml = zf.read(opf_path) if opf_path else b""
    except KeyError:
        opf_xml = b""
    if opf_xml:
        try:
            root = ET.fromstring(opf_xml)
            id2href = {}
            for el in root.iter():
                tag = el.tag.rsplit("}", 1)[-1].lower()
                if tag == "title" and not title and (el.text or "").strip():
                    title = el.text.strip()[:60]
                elif tag == "creator" and not author and (el.text or "").strip():
                    author = el.text.strip()[:60]
                elif tag == "item":
                    _id, _href = el.get("id"), el.get("href")
                    if _id and _href:
                        id2href[_id] = _href
            for el in root.iter():
                if el.tag.rsplit("}", 1)[-1].lower() == "itemref":
                    _href = id2href.get(el.get("idref"))
                    if _href:
                        order.append(_href)
        except ET.ParseError:
            src = opf_xml.decode("utf-8", errors="replace")   # 脏 OPF：正则退路
            m1 = re.search(r"<dc:title[^>]*>(.*?)</dc:title>", src, re.S | re.I)
            m2 = re.search(r"<dc:creator[^>]*>(.*?)</dc:creator>", src, re.S | re.I)
            if m1 and not title:
                title = re.sub(r"<[^>]*>", "", m1.group(1)).strip()[:60]
            if m2 and not author:
                author = re.sub(r"<[^>]*>", "", m2.group(1)).strip()[:60]
    if not order:   # 没 OPF 或没 spine：按名字序把整包 XHTML 当章（保底能读）
        order = sorted(n for n in names if n.lower().endswith((".xhtml", ".html", ".htm")))
    seen = set()
    chapters = []
    for href in order:
        p = _epub_zip_path(opf_dir, href)
        if not p or p in seen:
            continue
        seen.add(p)
        try:
            data = zf.read(p)
        except KeyError:
            continue
        t = _book_html_to_text(data)
        if t:
            chapters.append(t)
    zf.close()
    if not chapters:
        raise _BookBad("这本还带着锁，打不开——换个无 DRM 的版本试试")
    return title, author, _book_tidy("\n\n".join(chapters))


def _book_import_bytes(data, fname_in, fb64):
    """共读导入·字节路：epub/html 原始字节 → 文本 → files/books/book_{id}.txt。
    返回 (http_code, 响应体)；人话 400 全走 _BookBad。老 content 路不经过这里。"""
    btitle = str(data.get("title") or "").strip()[:60]
    bauthor = str(data.get("author") or "").strip()[:60]
    suffix = os.path.splitext(fname_in)[1].lower()
    if suffix not in (".epub", ".html", ".htm"):
        return 400, {"ok": False, "error": "这本书的格式还认不得（支持 epub/txt/md/html）"}
    if not fb64:
        return 400, {"ok": False, "error": "文件没读全，重传一下"}
    try:
        blob = base64.b64decode(fb64 + "=" * (-len(fb64) % 4), validate=True)
    except Exception:
        return 400, {"ok": False, "error": "文件没读全，重传一下"}
    if len(blob) > 8 * 1024 * 1024:
        return 400, {"ok": False, "error": "这本有点厚（>8MB），先劈开或换个版本"}
    try:
        if suffix == ".epub":
            opf_title, opf_author, text = _epub_to_text(blob)
        else:
            opf_title, opf_author, text = "", "", _book_html_to_text(blob)
    except _BookBad as e:
        return 400, {"ok": False, "error": str(e)}
    if not (text or "").strip():
        return 400, {"ok": False, "error": "这本提不出字来（可能是扫描版或加密的）——换个版本试试"}
    if len(text.encode("utf-8")) > 2 * 1024 * 1024:
        return 400, {"ok": False, "error": "这本有点厚（提字后>2MB），先劈开或换个版本"}
    final_title = opf_title or btitle
    final_author = opf_author or bauthor
    if not final_title:
        return 400, {"ok": False, "error": "书名和内容都得有"}
    bid = m.add_book(final_title, final_author)
    bookdir = os.path.join(BASE_DIR, "files", "books")
    os.makedirs(bookdir, exist_ok=True)
    fname = f"book_{bid}.txt"
    with open(os.path.join(bookdir, fname), "w", encoding="utf-8") as f:
        f.write(text)
    m.set_book_file(bid, fname)
    print(f"  [共读] 导入《{final_title}》（{suffix}，提字 {len(text)} 字符，files/books/{fname}）")
    return 200, {"ok": True, "id": bid}


# ── Latent 拒绝日志＋限速（9-23 小刀三连·刀3；借鉴 oliscatt/Latent-memory「拒绝日志格式」）──
# 四条：①4xx/5xx 各记一行「[拒绝] 状态码 原因 方法 路径 src=IP」；②路径剥 query（防 token
# 泄漏）、绝不记请求体/token；③同 IP 每分钟逐条最多 _REJECT_LOG_MAX 条，超出压制并明说——
# 首条即报、此后每满 _REJECT_REPORT_STEP 条补一行小结（K＝报时累计压制数，可核；行数上界
# ≈ 上限＋K/100，防日志被刷爆）；④正常 2xx 请求零新增输出。只进本地日志，obs 形状不动。
_REJECT_LOG_MAX = 30        # 同 IP 每分钟逐条上限（Latent「每分钟上限」）
_REJECT_REPORT_STEP = 100   # 压制期每满 N 条补一行小结（=100 时行数 ≈ 上限 + 1%；测试对账见报告）
_REJECT_STATE = {}          # {(ip, "YYYY-MM-DD HH:MM"): [记数, 压制数]}——过窗自动重建
_REJECT_LOCK = threading.Lock()


def _reject_line(ip, code, reason, method, path, now=None):
    """拒绝日志限速器：返回该落的行（""＝本分钟静默被压制）。纯记账纯函数（状态在
    _REJECT_STATE），不写流、不抛——测试可注入 now 直接对账节奏。"""
    minute = (now or datetime.now()).strftime("%Y-%m-%d %H:%M")
    key = (str(ip), minute)
    line = ""
    with _REJECT_LOCK:
        for k in [k for k in _REJECT_STATE if k[1] != minute]:   # 过窗旧桶清掉（防字典长胖）
            _REJECT_STATE.pop(k, None)
        n, sup = _REJECT_STATE.get(key, (0, 0))
        n += 1
        if n <= _REJECT_LOG_MAX:
            line = f"[拒绝] {code} {reason} {method} {path} src={ip}"
        else:
            sup += 1
            if sup == 1 or sup % _REJECT_REPORT_STEP == 0:
                line = (f"[拒绝] {code} {reason} {method} {path} src={ip}"
                        f"（本分钟已压制 {sup} 条）")
        _REJECT_STATE[key] = (n, sup)
    return line
