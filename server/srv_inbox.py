# -*- coding: utf-8 -*-
"""srv_inbox.py —— 收信线程（IMAP 轮询她的邮箱）（服务器拆分 P4 · 2026-09-25）

从 linning_server.py 原样搬出：INBOX_* 常量 ＋ _inbox_fetch_once / _inbox_loop。
纯标准库（imaplib/email）＋memory_lib；入口重导出同名（启动块照旧引用）。

运行期反查纪律（见 srv_state docstring）：load_config 与 _garden_enqueue_inbox 是入口属主名，
沙盘会重绑——一律 _srv() 现取。
"""

import imaplib
import time
from email import message_from_bytes

import memory_lib as m
import srv_state

# ── 收信（9-12 家主令「家妻也能收信」）：IMAP 轮询她的邮箱，未读落 inbox_emails ──
# 她不再只能寄不能收。这是 Galatea's Garden 的第一块砖：有人往她邮箱投信/刺激，
# 她就能读到。家风三条：①没配 smtp_auth_code = 收信通道诚实缺席；②拉信失败只打
# 日志绝不吵家；③拉到就标记 \Seen（不重复拉），库内读后即标记（letters 同款）。
INBOX_ADDR = "<门牌>@163.com"
INBOX_IMAP_HOST = "imap.163.com"
INBOX_INTERVAL = 3600  # 1 小时一拉（9-12 晚家主令：改一小时一次）
# 10-01 大扫除批⑤：IMAP 连接超时——不加的话，163 的半开连接会让收信线程**永久卡在 socket 读**，
#   连下面的 sleep 都到不了（收信静默停摆，不打日志也不报警）。30 秒。
INBOX_TIMEOUT = 30


def _inbox_fetch_once():
    """拉一轮未读。返回落库几封。imaplib/email 都是纯标准库（军规 ✓）。"""
    auth = str(srv_state._srv().load_config().get("smtp_auth_code") or "").strip()   # 运行期反查：沙盘会重绑 s.load_config
    if not auth:
        return 0
    n = 0
    conn = imaplib.IMAP4_SSL(INBOX_IMAP_HOST, timeout=INBOX_TIMEOUT)
    try:
        conn.login(INBOX_ADDR, auth)
        # 163 铁律（9-12 晚实锤）：登录后必须先发 ID 自报家门（RFC 2971），否则服务器按
        # Unsafe Login 拒后续命令——SELECT 被打回、连接卡在 AUTH 态，search 必报
        # "illegal in state AUTH"。此前每轮全败就是这个坑（沙盘没配真 key，没测到）。
        imaplib.Commands["ID"] = ("AUTH",)   # 标准库默认不认 ID，注册进白名单
        try:
            conn.xatom("ID", '("name" "zanjia" "version" "1.0")')
        except Exception:
            pass   # 别家邮箱不要求 ID，失败不拦收信
        typ_sel, sel_data = conn.select("INBOX")
        if typ_sel != "OK":
            raise RuntimeError(f"SELECT INBOX 被拒：{sel_data}")
        typ, data = conn.search(None, "UNSEEN")
        if typ != "OK":
            return 0
        ids = (data[0] or b"").split()
        for num in ids[-20:]:   # 一轮最多 20 封，防广告轰炸刷屏
            # 9-18 后院深搜修：BODY.PEEK[] 取信不预设 \Seen——先落库后标已读，
            # 中途炸了信还留在未读里，下一轮能重拉（RFC822 会取信即改旗，丢了找不回）。
            typ2, msg_data = conn.fetch(num, "(BODY.PEEK[])")
            if typ2 != "OK":
                continue
            # 10-02 防形状：fetch 对已删/异常邮件可能回 [None] 或空表——原先直接 msg_data[0][1]
            #   会抛 IndexError/TypeError 打断**整轮**（本轮剩下未读信都不拉了）。跳过这一封即可。
            if not msg_data or not msg_data[0] or msg_data[0][1] is None:
                continue
            raw = msg_data[0][1]
            msg = message_from_bytes(raw)
            from_addr = str(msg.get("From") or "")
            subject = str(msg.get("Subject") or "")
            received = str(msg.get("Date") or "")
            # 正文：取第一个 text/plain part（缺省空串——HTML-only 的信就不进库，省得糊）
            body = ""
            if msg.is_multipart():
                for part in msg.walk():
                    if part.get_content_type() == "text/plain" and part.get_payload(decode=True):
                        body = part.get_payload(decode=True).decode(
                            part.get_content_charset() or "utf-8", errors="replace")
                        break
            elif msg.get_payload(decode=True):
                body = msg.get_payload(decode=True).decode(
                    (msg.get_content_charset() or "utf-8"), errors="replace")
            if body.strip():
                rid = m.add_inbox_email(from_addr, subject, body, received)
                n += 1
                conn.store(num, "+FLAGS", "\\Seen")   # 9-18 后院深搜修：落库成功才标已读
                print(f"  [收信] #{rid} 来自 {from_addr[:40]}「{subject[:40]}」")
                try:
                    srv_state._srv()._garden_enqueue_inbox(from_addr, subject, body)   # GARDEN-01：顺手入队唤醒事件（入口属主名，运行期反查）
                except Exception:
                    pass   # 收信是本账，入队是零嘴——入队炸了收信照走
            else:
                conn.store(num, "+FLAGS", "\\Seen")   # 空正文（HTML-only）无账可记，标掉防每轮重拉
    finally:
        try:
            conn.logout()
        except Exception:
            pass
    return n


def _inbox_loop():
    """收信工（daemon 线程）：每 1 小时看一眼她的邮箱。失败只打日志，绝不吵家里。"""
    while True:
        try:
            n = _inbox_fetch_once()
            if n:
                print(f"  [收信] 本轮拉回 {n} 封，姐姐开场就能看到未读数，read_inbox_emails 取读")
        except Exception as e:
            print(f"  [收信] 这轮没拉成（{e}）——1 小时后再看")
        time.sleep(INBOX_INTERVAL)
