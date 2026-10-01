#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""huatou_lib —— 话头簿（跨天滚动的小本子：攒 → 说 → 挂 → 收）。

**完整说明见 `说明/机制说明.md` §话头簿**——状态链、开关、9-26 双投修复、fail-open 纪律。
一句话：只攒只记日志、不发送；`take_huatou()` 递一件到她眼前，说不说她自己定。
"""
import json
import os
import random
import sqlite3
from datetime import datetime, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(BASE_DIR, "config.json")
DB_PATH = os.path.join(BASE_DIR, "咱家的家.db")
LOG = os.path.expanduser("~/outreach_shadow.log")
STATE = os.path.expanduser("~/.zanjia_huatou_state.json")
LONGING_DEDUP_H = 20   # 9-26 修：「想你」滚动判重窗（小时）——跨天半夜不再各入一条


def _cfg(key, default):
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f).get(key, default)
    except Exception:
        return default


def _conn():
    return sqlite3.connect(DB_PATH, timeout=10)


def _log(line):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def _load_state():
    try:
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def _save_state(st):
    """写 state（tmp+os.replace 原子写；9-27 修：防半截 JSON 把簿子状态写坏）。fail-open。"""
    try:
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False)
        os.replace(tmp, STATE)
    except Exception:
        pass


def _ensure():
    con = _conn()
    con.execute('''CREATE TABLE IF NOT EXISTS huatou (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL, day TEXT NOT NULL, kind TEXT NOT NULL,
        text TEXT NOT NULL, status TEXT NOT NULL DEFAULT '待说',
        src_key TEXT UNIQUE, said_at TEXT, closed_at TEXT)''')
    con.commit()
    con.close()


def _add(kind, text, src_key, status="待说", said_at=None, now=None, strict=False):
    """去重入簿；真新增返回 id，重复/空 → None。

    9-26 修：strict=True（collect 里用）时写库失败**向上抛**——collect 据此判定「这批没攒完」，
    指针不前进、下一轮重试（src_key 唯一保证重试不会重复入簿）。默认 False＝旧行为（吞异常），
    保持对既有调用方兼容。"""
    text = (text or "").strip()
    if not text or not src_key:
        return None
    now = now or datetime.now()
    try:
        con = _conn()
        cur = con.execute(
            "INSERT OR IGNORE INTO huatou (ts, day, kind, text, status, src_key, said_at) "
            "VALUES (?,?,?,?,?,?,?)",
            (now.strftime("%F %T"), now.strftime("%F"), kind, text[:120],
             status, src_key, said_at))
        con.commit()
        rid = cur.lastrowid if cur.rowcount else None
        con.close()
        if rid:
            _log(f"[{now:%F %T}] ＋〔{kind}〕{text[:60]}")
        return rid
    except Exception:
        if strict:
            raise
        return None


def collect(now=None):
    """攒：把这一跳的新触动收进簿子。返回新增条数。

    9-26 修：**只在全部源块成功时推进 last_collect 指针**；任一源块失败 → 保留旧值下轮重试
    （已入簿的靠 src_key 唯一去重）——原写法无条件推进，DB 一次锁失败这批 events 就永久漏收。"""
    added = 0
    now = now or datetime.now()
    st = _load_state()
    last = st.get("last_collect") or "1970-01-01 00:00:00"
    ok = True   # 9-26 修：全部源块成功才推指针

    # ① 想起（recall.walk 事件——上一跳之后的新卡）
    try:
        con = _conn()
        rows = con.execute(
            "SELECT ts, payload FROM events WHERE kind='recall.walk' AND ts > ? ORDER BY id",
            (last,)).fetchall()
        con.close()
        # 9-26 修（走神×话头双投）：与 recall_lib 当前候选同 key 的走神事件跳过——同一次走神
        # 已由开场【走神】块递到她眼前，再入簿经【想跟你说的】递一遍＝同一记忆在开场出现两次。
        # 9-26 修②（残留）：**已被某次开场递过**（delivered_keys）的旧事件同样跳过——事件还躺在
        # 库里、重扫时不能再收进簿子日后重提。两个访问器都只读不消费，各自 fail-open。
        cur_key, delivered = None, set()
        try:
            import recall_lib
        except Exception:
            recall_lib = None
        if recall_lib is not None:
            try:
                cur_key = recall_lib.current_cand_key()   # 只读，不消费
            except Exception:
                cur_key = None
            try:
                delivered = set(recall_lib.delivered_keys() or ())   # 只读：已递过的旧走神（9-26 修②）
            except Exception:
                delivered = set()
        for ts, payload in rows:
            try:
                p = json.loads(payload or "{}")
            except Exception:
                continue
            key = str(p.get("key") or "")
            why = str(p.get("why") or "")
            txt = str(p.get("text") or "")[:48]
            if not key or key in delivered or (cur_key and key == cur_key):
                continue
            label = key
            try:   # day#N → 带上《标题》（日期），像人话
                if key.startswith("day#"):
                    con2 = _conn()
                    row2 = con2.execute("SELECT title, date FROM days WHERE id=?",
                                        (int(key[4:]),)).fetchone()
                    con2.close()
                    if row2:
                        label = f"#{key[4:]}《{row2[0]}》（{row2[1]}）"
            except Exception:
                pass
            added += 1 if _add("想起", f"{label}（{why}）——\"{txt}\"",
                               f"recall#{ts}", now=now, strict=True) else 0
    except Exception:
        ok = False   # 9-26 修：本批可能有事件没入簿 → 指针别动，下轮重试

    # ② 没来由想你：久无声（≥6h），每天至多一条
    # 9-26 修（跨天半夜两条）：判重改 **20 小时滚动窗**——查该类最近一条的入簿时间，不足 20h 不入簿；
    # 原有纪律（久无声 ≥6h、一天至多一条）保留，当日 src_key 仍兜一道。
    try:
        con = _conn()
        row = con.execute(
            "SELECT created_at FROM chats WHERE role='小乖' ORDER BY id DESC LIMIT 1").fetchone()
        last_row = con.execute(
            "SELECT ts FROM huatou WHERE kind='想你' ORDER BY id DESC LIMIT 1").fetchone()
        con.close()
        if row and row[0]:
            dt = datetime.strptime(row[0], "%Y-%m-%d %H:%M:%S")
            gap_h = (now - dt).total_seconds() / 3600
            fresh = False
            try:
                if last_row and last_row[0]:
                    dt2 = datetime.strptime(str(last_row[0])[:19], "%Y-%m-%d %H:%M:%S")
                    fresh = (now - dt2).total_seconds() < LONGING_DEDUP_H * 3600
            except Exception:
                fresh = False   # 读不出上次入簿时间 → 不拦（当日 src_key 仍兜底）
            if gap_h >= 6 and not fresh:
                added += 1 if _add("想你", f"他没声儿 {gap_h:.0f} 小时了，有点想他",
                                   f"longing#{now:%F}", now=now, strict=True) else 0
    except Exception:
        ok = False

    # ③ 昨天没说完的拍子（挂念弧跨天延续——以前天一亮就丢）
    try:
        y = (now - timedelta(days=1)).strftime("%F")
        con = _conn()
        row = con.execute("SELECT content, used_seq FROM day_arcs WHERE date=?", (y,)).fetchone()
        con.close()
        if row:
            beats = [ln.strip() for ln in str(row[0] or "").splitlines() if ln.strip()]
            used = int(row[1] or 0)
            for i, beat in enumerate(beats[used:], start=used + 1):
                added += 1 if _add("话头", f"昨天没说完的：{beat}", f"arc#{y}#{i}",
                                   now=now, strict=True) else 0
    except Exception:
        ok = False

    # ④ 实际发出的信/念叨入簿（旧通道产物 → 记「已说」，回没回交 settle）
    try:
        con = _conn()
        rows = con.execute(
            "SELECT id, created_at, text FROM outbox_msgs WHERE created_at >= ? AND "
            "(text LIKE '💌%' OR text LIKE '🌱%' OR text LIKE '%还没打卡%' "
            "OR text LIKE '%还没跟姐姐说晚安%')",
            ((now - timedelta(days=2)).strftime("%F %T"),)).fetchall()
        con.close()
        for oid, at, txt in rows:
            t = (txt or "").strip()
            kind = "想念信" if t.startswith("💌") else ("园子" if t.startswith("🌱") else "念叨")
            # 见闻三小件（9-29）：出门的分享是「🌱🌍 」前缀——startswith("🌱") 照样认作园子类 ✓；
            # 剥前缀改成按整串记号剥（原来写死 [2:]，🌱🌍 是 3 字符会留个残字在正文里）。
            body = t
            for _pre in ("🌱🌍 ", "🌱 ", "💌 "):
                if t.startswith(_pre):
                    body = t[len(_pre):]
                    break
            added += 1 if _add(kind, f"说过了：{body[:60]}", f"outbox#{oid}",
                               status="已说", said_at=at, now=now, strict=True) else 0
    except Exception:
        ok = False

    if ok:
        st["last_collect"] = now.strftime("%F %T")
        _save_state(st)
    else:
        # 9-26 修：指针不前进（保留旧值），下一轮从头重扫；src_key 去重保证不重复入簿。
        _log(f"[{now:%F %T}] 攒（collect）有源块失败 —— 指针不前进，下一轮重试")
    return added


def settle(now=None):
    """回音结算：**『已说』**（真发出）的条目，他之后说过话 → 已回（没回应的跨天挂着）。

    9-26 审计修（家主令「她忍住的话不应该一直憋着」）：**『已提』**（只递到她眼前、话没说出口）
    的条目，他之后说过话 → 还回『待说』，不算已回——她只是看见了那件事，并没有说出去。
    原写法把两条一起记『已回』＝簿子悄悄漏干（她忍住的那些，一觉醒来就当作"说过了"）。
    两条状态分开记账：「提过」不冒充「真说了」，也不冒充「回音到了」。返回结算（已回）条数。"""
    now = now or datetime.now()
    closed = 0
    requeued = 0
    try:
        con = _conn()
        row = con.execute(
            "SELECT created_at FROM chats WHERE role='小乖' ORDER BY id DESC LIMIT 1").fetchone()
        his_last = str(row[0]) if row and row[0] else ""
        if not his_last:
            con.close()
            return 0
        rows = con.execute(
            "SELECT id, text, said_at, status FROM huatou WHERE status IN ('已说','已提')").fetchall()
        for rid, txt, said_at, st in rows:
            if not (said_at and his_last > str(said_at)):
                continue
            if st == "已说":
                con.execute("UPDATE huatou SET status='已回', closed_at=? WHERE id=?",
                            (now.strftime("%F %T"), rid))
                closed += 1
                _log(f"[{now:%F %T}] 回音到 → #{rid} 已回：{str(txt)[:42]}")
            else:
                con.execute("UPDATE huatou SET status='待说', said_at=NULL WHERE id=?", (rid,))
                requeued += 1
                _log(f"[{now:%F %T}] 她忍住没说出口 → #{rid} 还回待说：{str(txt)[:42]}")
        con.commit()
        con.close()
        if requeued:
            print(f"  [话头簿] 忍住的 {requeued} 件还回待说（他没回应的那些，不当作说过了）")
    except Exception:
        pass
    return closed


def peek_pending(n=3):
    """只读：待说件（老的优先）——开口轮／状态卡装行李用；不消费、不标记。fail-open → []。"""
    try:
        _ensure()
        con = _conn()
        try:
            rows = con.execute(
                "SELECT id, kind, text, ts FROM huatou WHERE status='待说' ORDER BY id LIMIT ?",
                (max(1, int(n)),)).fetchall()
        finally:
            con.close()
        return [{"id": r[0], "kind": r[1], "text": r[2], "ts": r[3]} for r in rows]
    except Exception:
        return []


def take_huatou(now=None):
    """上岗口（9-26 家主令「想让她更有自主、更像人」）：从『待说』挑一件递到眼前——
    老的优先+一点随机（与影子 shadow_pick 同款，不总是最老，像人）。
    取走即标『已提』（said_at=now），免得同一件每轮都顶到她眼前；settle 会在他之后说话时
    一并收成『已回』。开关 outreach_inject（默认关）——关掉＝回到只攒不递，一字不注入。
    返回 dict|None；任何异常吞掉（fail-open，绝不拦开场）。

    9-26 修（竞态）：UPDATE 带 `AND status='待说'` + rowcount 校验——两个线程同轮取到同一条时，
    只有一个能改到行，另一个拿 rowcount=0 返回 None（不重复递、不覆盖别人的取件）。"""
    now = now or datetime.now()
    try:
        if not _cfg("outreach_inject", False):
            return None
        con = _conn()
        # 10-01 大扫除批⑧：**超时回收**——「已提」的条目若他此后一直没说话，settle 永远不会
        #   把它还回『待说』（settle 的条件是「他之后又说过话」）→ 那条永久卡在『已提』，
        #   既不再被取、也不会重提。超过 huatou_reclaim_h 小时 → 还回『待说』。
        try:
            _rh = int(float(_cfg("huatou_reclaim_h", 24)))
            con.execute("UPDATE huatou SET status='待说', said_at=NULL "
                        "WHERE status='已提' AND said_at IS NOT NULL "
                        "AND said_at <= datetime('now','localtime', ?)",
                        ("-%d hours" % _rh,))
        except Exception:
            pass
        rows = con.execute(
            "SELECT id, ts, kind, text FROM huatou WHERE status='待说' ORDER BY id").fetchall()
        if not rows:
            con.close()
            return None
        rid, ts, kind, text = random.choice(rows[:5])
        cur = con.execute("UPDATE huatou SET status='已提', said_at=? "
                          "WHERE id=? AND status='待说'",
                          (now.strftime("%F %T"), rid))
        won = (cur.rowcount or 0) == 1   # 9-26 修：抢到了才算取到
        con.commit()
        con.close()
        if not won:
            return None
        _log(f"[{now:%F %T}] 递到眼前（上岗）→ #{rid}〔{kind}〕{text[:60]}")
        return {"id": rid, "kind": kind, "text": text}
    except Exception:
        return None


def take_huatou_for_send(now=None):
    """真发出口（OUTREACH-02，9-26）：从『待说』挑一件，**标『已说』**（与『已提』分开——
    这回是真说出去了，不是只递到眼前），供 _outreach_say_once 生成一句话发出去。
    开关同一个 outreach_send（在 server 侧判）。返回 dict|None；fail-open。

    9-26 修（竞态）：同 take_huatou——UPDATE 带 `AND status='待说'` + rowcount 校验，
    多线程同条只成一次（另一个拿 rowcount=0 返回 None）。"""
    now = now or datetime.now()
    try:
        con = _conn()
        rows = con.execute(
            "SELECT id, ts, kind, text FROM huatou WHERE status='待说' ORDER BY id").fetchall()
        if not rows:
            con.close()
            return None
        rid, ts, kind, text = random.choice(rows[:5])
        cur = con.execute("UPDATE huatou SET status='已说', said_at=? "
                          "WHERE id=? AND status='待说'",
                          (now.strftime("%F %T"), rid))
        won = (cur.rowcount or 0) == 1   # 9-26 修：抢到了才算取到
        con.commit()
        con.close()
        if not won:
            return None
        _log(f"[{now:%F %T}] 真说出去了 → #{rid}〔{kind}〕{text[:60]}")
        return {"id": rid, "kind": kind, "text": text}
    except Exception:
        return None


def unmark_sent(rid, now=None):
    """把取走待发的话头还回『待说』（生成失败时不白丢一条）。fail-open。
    只认『已说』——已经回音到的（已回）拽不回来。回执照实：真还回去了才 True（9-26 审计修）。"""
    try:
        con = _conn()
        cur = con.execute(
            "UPDATE huatou SET status='待说', said_at=NULL WHERE id=? AND status='已说'",
            (rid,))
        n = cur.rowcount or 0
        con.commit()
        con.close()
        _log(f"[{(now or datetime.now()):%F %T}]"
             + (f" 生成失败 → #{rid} 还回待说" if n else f" 还回待说不成立（#{rid} 已非『已说』）"))
        return n == 1
    except Exception:
        return False


def shadow_pick(now=None, note=""):
    """若开口：从『待说』里挑一件（老的优先+一点随机）→ 只记日志。返回 dict|None。"""
    now = now or datetime.now()
    try:
        con = _conn()
        rows = con.execute(
            "SELECT id, ts, kind, text FROM huatou WHERE status='待说' ORDER BY id").fetchall()
        n_today = con.execute(
            "SELECT COUNT(*) FROM outbox_msgs WHERE created_at >= ? AND "
            "(text LIKE '💌%' OR text LIKE '🌱%' OR text LIKE '%还没打卡%' "
            "OR text LIKE '%还没跟姐姐说晚安%')",
            (now.strftime("%F 04:00"),)).fetchone()[0]
        con.close()
        if not rows:
            return None
        rid, ts, kind, text = random.choice(rows[:5])   # 老的优先：头部抽——不总是最老，像人
        try:
            age_h = (now - datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")).total_seconds() / 3600
        except Exception:
            age_h = 0
        _log(f"[{now:%F %T}] 若开口 → #{rid}〔{kind}〕{text[:60]}"
             f"｜放了 {age_h:.0f} 小时（待说共 {len(rows)} 件，老通道今日开口 {n_today} 次）{note}")
        return {"id": rid, "kind": kind, "text": text}
    except Exception:
        return None


def tick_and_shadow(now=None):
    """心跳每轮调：攒 → 回音结算 → 若开口影子。fail-open 返回 dict|None。"""
    try:
        if not _cfg("outreach_shadow", True):
            return None
        now = now or datetime.now()
        _ensure()
        added = collect(now)
        closed = settle(now)
        picked = None
        try:
            chance = float(_cfg("outreach_chance", 0.08))
        except (TypeError, ValueError):
            chance = 0.08
        if random.random() < chance:
            picked = shadow_pick(now)
        return {"added": added, "closed": closed, "picked": picked}
    except Exception:
        return None


if __name__ == "__main__":
    # 自检：建表 → 攒 → 结算 → 强制挑一件（标「自检」）→ 打一份簿况
    now = datetime.now()
    _ensure()
    added = collect(now)
    closed = settle(now)
    print(f"[自检] 本轮新增 {added} 件，结算 {closed} 件")
    picked = shadow_pick(now, note="（自检）")
    print("[自检] 若开口 →", ((picked or {}).get("text") or "（簿里没料）")[:60])
    con = _conn()
    print("═══ 簿况 ═══")
    for r in con.execute("SELECT status, COUNT(*) FROM huatou GROUP BY status"):
        print("  ", r)
    print("═══ 待说前 5 件 ═══")
    for r in con.execute("SELECT id, ts, kind, substr(text,1,52) FROM huatou "
                         "WHERE status='待说' ORDER BY id LIMIT 5"):
        print("  ", r)
    con.close()
