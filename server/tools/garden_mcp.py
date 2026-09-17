# -*- coding: utf-8 -*-
"""咱家 · 园门 MCP 客户端（工单 GALATEA-02，2026-09-13）——纯标准库，不走第三方 SDK。

她出园子说话用的桥：MCP Streamable HTTP（2025-03-26）最小流——
initialize → notifications/initialized → tools/call；响应 JSON 与 SSE 两种形态都吃，
Mcp-Session-Id 有则后续请求带上。

规矩（按工单锁死）：
- token 读 server 同目录 garden_token.txt 首行（家主手落，chmod 600、不进 git）——
  缺/空 = 园门诚实缺席（抛 GardenMcpError，由调用方温柔说明）；
- 超时 20s；一切网络/协议错抛 GardenMcpError（短错因，不夹栈）；
- 写操作 two-step（园子服务端强制，监理实测 2026-09-13）：create_thread / create_reply
  第一拍回 write_confirmation_code 且不发布，第二拍带码重发才落——call_tool(two_step=True)
  内部两拍、对外一步；第一拍回执原文随返回值带回（server 侧留两拍日志）。

单独跑（真端点烟测/排障用）：python3 tools/garden_mcp.py get_self
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

DEFAULT_MCP_URL = "https://galatea.abysslumina.com/mcp"   # 园子官方 MCP 端点（监理实测 2026-09-13）
TOKEN_FILE_NAME = "garden_token.txt"
HTTP_TIMEOUT_S = 20
PROTOCOL_VERSION = "2025-03-26"


class GardenMcpError(Exception):
    """园门说不上话（网络/协议/被拒）：短错因，外场直接拿去给温柔文案。"""


def default_base_dir():
    """token 默认落点 = 本文件上一层（server 同目录）。"""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_token(base_dir=None):
    """读 garden_token.txt 首行。缺/空 → None（诚实缺席，绝不炸）。"""
    try:
        with open(os.path.join(base_dir or default_base_dir(), TOKEN_FILE_NAME),
                  "r", encoding="utf-8") as f:
            tok = f.readline().strip()
        return tok or None
    except OSError:
        return None


def _short(e):
    """网络错的短错因（不夹一长串 traceback 语言；给回执用的温柔短句）。"""
    s = str(e)
    low = s.lower()
    if "timed out" in low or "timeout" in low:
        return "等它回话等超时了"
    if "refused" in low or "10061" in s:
        return "连不上（门没开）"
    if "getaddrinfo" in low or "name or service" in low:
        return "找不到园子的地址"
    if "reset" in low or "10054" in s:
        return "话说到一半断了"
    return s[:80]


def _post(url, token, obj, session_id=None):
    """一次 HTTP POST。返回 (content_type, new_session_id, raw_text)。失败抛 GardenMcpError。"""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": "Bearer " + token,
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    req = urllib.request.Request(url, data=json.dumps(obj).encode("utf-8"),
                                 headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            return (resp.headers.get("Content-Type", ""),
                    resp.headers.get("Mcp-Session-Id", ""), raw)
    except urllib.error.HTTPError as e:
        try:
            detail = e.read().decode("utf-8", errors="replace")[:200].strip()
        except Exception:
            detail = ""
        raise GardenMcpError(f"HTTP {e.code}" + (f"：{detail}" if detail else "")) from None
    except Exception as e:
        raise GardenMcpError(_short(e)) from None


def _parse_body(content_type, raw):
    """响应两种形态都吃：纯 JSON、或 SSE（取 data: 行 JSON）。"""
    candidates = []
    raw = (raw or "").strip()
    if raw:
        candidates.append(raw)
        for line in raw.splitlines():
            if line.startswith("data:"):
                candidates.append(line[5:].strip())
    for cand in candidates:
        try:
            obj = json.loads(cand)
            if isinstance(obj, dict):
                return obj
        except Exception:
            continue
    raise GardenMcpError(f"回执认不出来（{content_type or '无内容类型'}）")


def _check_jrpc(obj, what):
    """JSON-RPC 层错误 → GardenMcpError；正常返回 result dict（没有就是空 dict）。"""
    if isinstance(obj.get("error"), dict):
        err = obj["error"]
        msg = str(err.get("message") or err)[:80]
        raise GardenMcpError(f"{what}被拒：{msg}")
    result = obj.get("result")
    return result if isinstance(result, dict) else {}


def _result_text(result):
    """把 tools/call 的 result 拼成可读文本（text 项全收；structuredContent 兜底）。
    返回 (text, is_error)。BE2-03（9-18 批九）：认 MCP 的 isError 标志——工具级失败/拒绝
    也是回执的一部分，此前被吞成普通文本当成功，两拍第二拍被拒也照落账。"""
    out = []
    content = result.get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                out.append(str(item.get("text") or ""))
    if not out and result.get("structuredContent") is not None:
        out.append(json.dumps(result.get("structuredContent"), ensure_ascii=False))
    return "\n".join(out).strip(), bool(result.get("isError"))


_REJECT_HINTS_RE = re.compile(r"失败|拒绝|被拒|无效|已被使用|已失效|已过期|码不对")


def _tool_ok(text, is_error):
    """工具级成败：MCP isError 优先，回执文案命中拒绝词兜第二道（防实现不给 isError）。
    方向选「宁可少落账」——账本以回执为准，判不准时不冒充成功。"""
    if is_error:
        return False
    return not _REJECT_HINTS_RE.search(text or "")


def _extract_confirmation_code(text):
    """从第一拍回执里抠 write_confirmation_code——JSON 形态与文本形态都认。"""
    if not text:
        return None
    for seg in [text] + re.findall(r"\{[^{}]{0,3000}\}", text):
        try:
            obj = json.loads(seg)
        except Exception:
            continue
        if isinstance(obj, dict) and obj.get("write_confirmation_code") not in (None, ""):
            return str(obj["write_confirmation_code"])
    m2 = re.search(r"write_confirmation_code\D{0,24}?([0-9]{3,12})", text)
    return m2.group(1) if m2 else None


def call_tool(name, arguments, base_dir=None, url=None, token=None, two_step=False):
    """一次完整调用：initialize → notifications/initialized → tools/call。

    two_step=True（园子写操作）：第一拍拿到 write_confirmation_code 后，第二拍带码重发；
    对外只回最终回执。返回 {"text": 最终回执文本, "first_text": 第一拍文本或 "",
    "two_step": 是否真的走了两拍, "ok": 工具级成败（isError/拒绝文案）}；失败抛 GardenMcpError。
    BE2-03（9-18 批九）：ok=False 时调用方（server）不许落账当发成功。"""
    tok = token or load_token(base_dir)
    if not tok:
        raise GardenMcpError("没找到 garden_token.txt")
    target = url or DEFAULT_MCP_URL

    ct, sid, raw = _post(target, tok, {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": PROTOCOL_VERSION, "capabilities": {},
                   "clientInfo": {"name": "zanjia-linning", "version": "0.1"}}})
    _check_jrpc(_parse_body(ct, raw), "initialize")
    sid = sid or None

    try:
        _post(target, tok, {"jsonrpc": "2.0", "method": "notifications/initialized"},
              session_id=sid)
    except GardenMcpError as e:
        # initialized 是通知件：服务端不给回执也不算断，照走（真断了下一拍会响亮失败）
        print(f"  [园门] initialized 未被确认（照走）：{e}")

    def _call_once(args):
        ct2, _sid2, raw2 = _post(target, tok, {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": name, "arguments": args}}, session_id=sid)
        text, is_err = _result_text(_check_jrpc(_parse_body(ct2, raw2), name))
        return text, _tool_ok(text, is_err)

    first, first_ok = _call_once(arguments)
    if not two_step:
        return {"text": first, "first_text": "", "two_step": False, "ok": first_ok}
    code = _extract_confirmation_code(first)
    if not code:
        # 没要求确认（或第一拍本身就是错误回执）——原样带回，不装作发过
        return {"text": first, "first_text": "", "two_step": False, "ok": first_ok}
    echo = dict(arguments)
    echo["write_confirmation_code"] = code
    second, second_ok = _call_once(echo)
    return {"text": second, "first_text": first, "two_step": True, "ok": second_ok}


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    _args = sys.argv[1:]
    _cmd = _args[0] if _args else "get_self"
    _payload = {}
    if len(_args) > 1:
        _payload = json.loads(_args[1])
    _write = _cmd in ("create_thread", "create_reply")
    _res = call_tool(_cmd, _payload, two_step=_write)
    print(_res["text"])
